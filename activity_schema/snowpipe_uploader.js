#!/usr/bin/env node
/**
 * Snowpipe Streaming Uploader
 * Processes NDJSON queue files and uploads to Snowflake with deduplication
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);

class SnowpipeUploader {
    constructor(config = {}) {
        // Configuration
        this.queueDir = config.queueDir || '/var/claude/queue';
        this.snowConnection = config.snowConnection || 'poc';
        this.batchSize = config.batchSize || 1000;
        this.uploadInterval = config.uploadInterval || 5000; // 5 seconds
        this.maxRetries = config.maxRetries || 3;
        
        // Snowflake CLI path
        this.snowCmd = config.snowCmd || '/Library/Frameworks/Python.framework/Versions/3.12/bin/snow';
        
        // State
        this.isProcessing = false;
        this.stats = {
            filesProcessed: 0,
            eventsUploaded: 0,
            duplicatesSkipped: 0,
            errors: 0,
            lastUploadTime: null,
            avgUploadLatency: 0
        };
        
        // Start processing loop
        this.startProcessingLoop();
    }
    
    /**
     * Start the processing loop
     */
    startProcessingLoop() {
        setInterval(async () => {
            if (!this.isProcessing) {
                await this.processQueue();
            }
        }, this.uploadInterval);
        
        console.log(`Snowpipe uploader started. Checking queue every ${this.uploadInterval}ms`);
    }
    
    /**
     * Process all ready files in the queue
     */
    async processQueue() {
        this.isProcessing = true;
        const readyFile = path.join(this.queueDir, '.ready');
        
        try {
            if (!fs.existsSync(readyFile)) {
                this.isProcessing = false;
                return;
            }
            
            // Read all ready files
            const lines = fs.readFileSync(readyFile, 'utf8')
                .split('\n')
                .filter(l => l);
            
            if (lines.length === 0) {
                this.isProcessing = false;
                return;
            }
            
            console.log(`Processing ${lines.length} queue files...`);
            
            // Process each file
            const processedFiles = [];
            for (const line of lines) {
                try {
                    const entry = JSON.parse(line);
                    const success = await this.processFile(entry.file, entry.offset || 0);
                    
                    if (success) {
                        processedFiles.push(entry.file);
                        this.stats.filesProcessed++;
                    }
                } catch (err) {
                    console.error(`Error processing entry: ${line}`, err);
                    this.stats.errors++;
                }
            }
            
            // Remove processed entries from ready file
            if (processedFiles.length > 0) {
                const remainingLines = lines.filter(line => {
                    const entry = JSON.parse(line);
                    return !processedFiles.includes(entry.file);
                });
                
                if (remainingLines.length > 0) {
                    fs.writeFileSync(readyFile, remainingLines.join('\n') + '\n');
                } else {
                    fs.unlinkSync(readyFile);
                }
                
                // Clean up processed files
                for (const file of processedFiles) {
                    this.archiveProcessedFile(file);
                }
            }
            
        } catch (err) {
            console.error('Error processing queue:', err);
            this.stats.errors++;
        } finally {
            this.isProcessing = false;
        }
    }
    
    /**
     * Process a single queue file
     */
    async processFile(filePath, offset = 0) {
        console.log(`Processing file: ${filePath} from offset ${offset}`);
        
        if (!fs.existsSync(filePath)) {
            console.warn(`File not found: ${filePath}`);
            return false;
        }
        
        const events = [];
        const fileStream = fs.createReadStream(filePath, { start: offset });
        const rl = readline.createInterface({
            input: fileStream,
            crlfDelay: Infinity
        });
        
        // Read events from file
        for await (const line of rl) {
            try {
                const event = JSON.parse(line);
                events.push(event);
                
                // Upload in batches
                if (events.length >= this.batchSize) {
                    await this.uploadBatch(events.splice(0, this.batchSize));
                }
            } catch (err) {
                console.error(`Error parsing line: ${line}`, err);
            }
        }
        
        // Upload remaining events
        if (events.length > 0) {
            await this.uploadBatch(events);
        }
        
        return true;
    }
    
    /**
     * Upload a batch of events to Snowflake with deduplication
     */
    async uploadBatch(events) {
        if (events.length === 0) return;
        
        const startTime = Date.now();
        console.log(`Uploading batch of ${events.length} events...`);
        
        // Generate MERGE statement for deduplication
        const mergeStatements = events.map(event => {
            // Escape single quotes in JSON
            const featureJson = JSON.stringify(event.feature_json || {}).replace(/'/g, "''");
            
            return `
                SELECT 
                    '${event.activity_id}' as activity_id,
                    '${event.ts || new Date().toISOString()}' as ts,
                    '${event.activity}' as activity,
                    '${event.customer}' as customer,
                    '${event.anonymous_customer_id || 'unknown'}' as anonymous_customer_id,
                    PARSE_JSON('${featureJson}') as feature_json,
                    ${event.revenue_impact || 0} as revenue_impact,
                    ${event.link ? `'${event.link}'` : 'NULL'} as link
            `;
        }).join(' UNION ALL ');
        
        const sql = `
            MERGE INTO CLAUDE_LOGS.ACTIVITIES.CLAUDE_STREAM_V2 target
            USING (
                ${mergeStatements}
            ) source
            ON target.activity_id = source.activity_id
            WHEN NOT MATCHED THEN
                INSERT (
                    activity_id, ts, activity, customer, 
                    anonymous_customer_id, feature_json, 
                    revenue_impact, link
                ) VALUES (
                    source.activity_id, source.ts, source.activity, 
                    source.customer, source.anonymous_customer_id, 
                    source.feature_json, source.revenue_impact, source.link
                );
        `;
        
        // Execute with retries
        let retries = 0;
        let success = false;
        
        while (retries < this.maxRetries && !success) {
            try {
                // Write SQL to temp file (to handle large batches)
                const tempFile = path.join(this.queueDir, `batch_${Date.now()}.sql`);
                fs.writeFileSync(tempFile, sql);
                
                // Execute via Snowflake CLI
                const { stdout, stderr } = await execAsync(
                    `${this.snowCmd} sql -c ${this.snowConnection} -f ${tempFile} 2>/dev/null`
                );
                
                // Clean up temp file
                fs.unlinkSync(tempFile);
                
                // Parse result
                if (stdout.includes('number of rows inserted') || stdout.includes('0 Row(s) produced')) {
                    const inserted = this.parseInsertedCount(stdout);
                    const skipped = events.length - inserted;
                    
                    this.stats.eventsUploaded += inserted;
                    this.stats.duplicatesSkipped += skipped;
                    
                    console.log(`Uploaded ${inserted} events, skipped ${skipped} duplicates`);
                    success = true;
                } else {
                    throw new Error(`Unexpected output: ${stdout}`);
                }
                
            } catch (err) {
                retries++;
                console.error(`Upload attempt ${retries} failed:`, err.message);
                
                if (retries < this.maxRetries) {
                    // Exponential backoff
                    await new Promise(resolve => setTimeout(resolve, Math.pow(2, retries) * 1000));
                } else {
                    this.stats.errors++;
                    throw err;
                }
            }
        }
        
        // Update latency stats
        const latency = Date.now() - startTime;
        this.stats.lastUploadTime = new Date().toISOString();
        this.stats.avgUploadLatency = this.stats.avgUploadLatency * 0.9 + latency * 0.1;
        
        return success;
    }
    
    /**
     * Parse inserted row count from Snowflake output
     */
    parseInsertedCount(output) {
        const match = output.match(/(\d+)\s+Row\(s\)\s+produced/);
        if (match) {
            return parseInt(match[1], 10);
        }
        
        const mergeMatch = output.match(/number of rows inserted:\s*(\d+)/);
        if (mergeMatch) {
            return parseInt(mergeMatch[1], 10);
        }
        
        return 0;
    }
    
    /**
     * Archive processed file
     */
    archiveProcessedFile(filePath) {
        const archiveDir = path.join(this.queueDir, 'archive');
        
        // Create archive directory if needed
        if (!fs.existsSync(archiveDir)) {
            fs.mkdirSync(archiveDir, { recursive: true });
        }
        
        // Move file to archive with timestamp
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const archivePath = path.join(archiveDir, `processed_${timestamp}_${path.basename(filePath)}`);
        
        try {
            fs.renameSync(filePath, archivePath);
            console.log(`Archived processed file: ${archivePath}`);
            
            // Clean up old archives (keep last 24 hours)
            this.cleanOldArchives(archiveDir);
        } catch (err) {
            console.error(`Error archiving file ${filePath}:`, err);
            // Try to delete if can't move
            try {
                fs.unlinkSync(filePath);
            } catch (deleteErr) {
                console.error(`Error deleting file ${filePath}:`, deleteErr);
            }
        }
    }
    
    /**
     * Clean up old archive files
     */
    cleanOldArchives(archiveDir) {
        const maxAge = 24 * 60 * 60 * 1000; // 24 hours
        const now = Date.now();
        
        const files = fs.readdirSync(archiveDir);
        for (const file of files) {
            const filePath = path.join(archiveDir, file);
            const stats = fs.statSync(filePath);
            
            if (now - stats.mtime.getTime() > maxAge) {
                fs.unlinkSync(filePath);
                console.log(`Deleted old archive: ${file}`);
            }
        }
    }
    
    /**
     * Get uploader statistics
     */
    getStats() {
        return {
            ...this.stats,
            isProcessing: this.isProcessing,
            queueDir: this.queueDir
        };
    }
    
    /**
     * Graceful shutdown
     */
    async shutdown() {
        console.log('Shutting down uploader...');
        
        // Wait for current processing to complete
        while (this.isProcessing) {
            await new Promise(resolve => setTimeout(resolve, 100));
        }
        
        console.log('Uploader shutdown complete. Stats:', this.getStats());
    }
}

// Export for use in other modules
module.exports = SnowpipeUploader;

// If run directly, start standalone uploader
if (require.main === module) {
    const uploader = new SnowpipeUploader({
        queueDir: process.env.QUEUE_DIR || '/tmp/claude_queue',
        snowConnection: process.env.SNOW_CONNECTION || 'poc'
    });
    
    // Handle shutdown signals
    process.on('SIGINT', async () => {
        await uploader.shutdown();
        process.exit(0);
    });
    
    process.on('SIGTERM', async () => {
        await uploader.shutdown();
        process.exit(0);
    });
    
    console.log('Snowpipe uploader started. Processing queue...');
    
    // Report stats periodically
    setInterval(() => {
        console.log('Uploader stats:', uploader.getStats());
    }, 30000); // Every 30 seconds
}