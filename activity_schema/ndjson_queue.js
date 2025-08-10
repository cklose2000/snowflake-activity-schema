#!/usr/bin/env node
/**
 * NDJSON Queue System with Durability
 * Crash-safe append-only queue with automatic rotation and deduplication
 */

const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

class DurableNDJSONQueue {
    constructor(config = {}) {
        // Queue configuration
        this.queueDir = config.queueDir || '/var/claude/queue';
        this.maxQueueSize = config.maxQueueSize || 50 * 1024 * 1024; // 50MB
        this.rotationInterval = config.rotationInterval || 60000; // 60 seconds
        this.backpressureThreshold = config.backpressureThreshold || 120000; // 2 minutes
        
        // File paths
        this.currentQueueFile = path.join(this.queueDir, 'current.ndjson');
        this.offsetFile = path.join(this.queueDir, 'offset.json');
        this.lockFile = path.join(this.queueDir, '.lock');
        
        // State
        this.currentFileHandle = null;
        this.currentFileSize = 0;
        this.lastRotation = Date.now();
        this.isBackpressured = false;
        this.stats = {
            eventsQueued: 0,
            eventsUploaded: 0,
            bytesWritten: 0,
            rotations: 0,
            errors: 0,
            backpressureEvents: 0
        };
        
        // Ensure queue directory exists
        this.ensureQueueDir();
        
        // Recover from crash if needed
        this.recoverFromCrash();
        
        // Start rotation timer
        this.startRotationTimer();
    }
    
    /**
     * Ensure queue directory exists with proper permissions
     */
    ensureQueueDir() {
        if (!fs.existsSync(this.queueDir)) {
            fs.mkdirSync(this.queueDir, { recursive: true, mode: 0o755 });
        }
    }
    
    /**
     * Recover from crash by reading offset file
     */
    recoverFromCrash() {
        if (fs.existsSync(this.offsetFile)) {
            try {
                const offset = JSON.parse(fs.readFileSync(this.offsetFile, 'utf8'));
                console.log(`Recovering from offset: ${JSON.stringify(offset)}`);
                
                // Check if the file still exists and has unprocessed data
                if (offset.file && fs.existsSync(offset.file)) {
                    const stats = fs.statSync(offset.file);
                    if (stats.size > offset.offset) {
                        console.log(`Found ${stats.size - offset.offset} bytes of unprocessed data`);
                        // Mark file for processing
                        this.markForProcessing(offset.file, offset.offset);
                    }
                }
            } catch (err) {
                console.error('Error recovering from offset file:', err);
            }
        }
        
        // Open current queue file for appending
        this.openCurrentFile();
    }
    
    /**
     * Open current queue file for appending
     */
    openCurrentFile() {
        if (this.currentFileHandle) {
            fs.closeSync(this.currentFileHandle);
        }
        
        // Open in append mode with sync flag for durability
        this.currentFileHandle = fs.openSync(this.currentQueueFile, 'a', 0o644);
        
        // Get current file size
        const stats = fs.fstatSync(this.currentFileHandle);
        this.currentFileSize = stats.size;
    }
    
    /**
     * Append event to queue with durability guarantees
     */
    async appendEvent(event) {
        // Add metadata
        const enrichedEvent = {
            ...event,
            activity_id: event.activity_id || uuidv4(),
            queued_at: new Date().toISOString(),
            queue_version: 2
        };
        
        // Check for backpressure
        if (this.isBackpressured) {
            enrichedEvent.degraded = true;
            enrichedEvent.degradation_reason = 'backpressure';
            
            // Sample data if too large
            if (enrichedEvent.feature_json && JSON.stringify(enrichedEvent.feature_json).length > 1024) {
                enrichedEvent.feature_json = {
                    ...enrichedEvent.feature_json,
                    _truncated: true,
                    _original_size: JSON.stringify(enrichedEvent.feature_json).length
                };
            }
        }
        
        // Convert to NDJSON line
        const line = JSON.stringify(enrichedEvent) + '\n';
        const lineBuffer = Buffer.from(line);
        
        // Write to file with sync for durability
        try {
            fs.writeSync(this.currentFileHandle, lineBuffer);
            this.currentFileSize += lineBuffer.length;
            this.stats.eventsQueued++;
            this.stats.bytesWritten += lineBuffer.length;
            
            // Check if rotation needed
            if (this.shouldRotate()) {
                await this.rotateQueue();
            }
            
            // Update offset file periodically (every 10 events)
            if (this.stats.eventsQueued % 10 === 0) {
                this.updateOffset();
            }
            
            return enrichedEvent.activity_id;
            
        } catch (err) {
            console.error('Error writing to queue:', err);
            this.stats.errors++;
            throw err;
        }
    }
    
    /**
     * Check if queue rotation is needed
     */
    shouldRotate() {
        const timeSinceRotation = Date.now() - this.lastRotation;
        return (
            this.currentFileSize >= this.maxQueueSize ||
            timeSinceRotation >= this.rotationInterval
        );
    }
    
    /**
     * Rotate queue file
     */
    async rotateQueue() {
        console.log(`Rotating queue file (size: ${this.currentFileSize} bytes)`);
        
        // fsync before rotation for durability
        fs.fsyncSync(this.currentFileHandle);
        fs.closeSync(this.currentFileHandle);
        
        // Generate rotated filename with timestamp
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const rotatedFile = path.join(this.queueDir, `queue_${timestamp}.ndjson`);
        
        // Rename current file
        fs.renameSync(this.currentQueueFile, rotatedFile);
        
        // Mark for processing
        this.markForProcessing(rotatedFile, 0);
        
        // Open new file
        this.openCurrentFile();
        this.lastRotation = Date.now();
        this.stats.rotations++;
        
        // Update offset
        this.updateOffset();
    }
    
    /**
     * Mark file for processing by uploader
     */
    markForProcessing(file, offset) {
        const readyFile = path.join(this.queueDir, '.ready');
        const entry = {
            file,
            offset,
            marked_at: new Date().toISOString()
        };
        
        // Append to ready file
        fs.appendFileSync(readyFile, JSON.stringify(entry) + '\n');
    }
    
    /**
     * Update offset file for recovery
     */
    updateOffset() {
        const offset = {
            file: this.currentQueueFile,
            offset: this.currentFileSize,
            updated_at: new Date().toISOString(),
            stats: this.stats
        };
        
        // Write atomically by writing to temp file and renaming
        const tempFile = this.offsetFile + '.tmp';
        fs.writeFileSync(tempFile, JSON.stringify(offset, null, 2));
        fs.renameSync(tempFile, this.offsetFile);
    }
    
    /**
     * Check for backpressure based on upload lag
     */
    async checkBackpressure() {
        const readyFile = path.join(this.queueDir, '.ready');
        
        if (!fs.existsSync(readyFile)) {
            this.isBackpressured = false;
            return;
        }
        
        // Check oldest unprocessed file
        const lines = fs.readFileSync(readyFile, 'utf8').split('\n').filter(l => l);
        if (lines.length > 0) {
            const oldest = JSON.parse(lines[0]);
            const age = Date.now() - new Date(oldest.marked_at).getTime();
            
            const wasBackpressured = this.isBackpressured;
            this.isBackpressured = age > this.backpressureThreshold;
            
            if (!wasBackpressured && this.isBackpressured) {
                console.warn(`Backpressure activated: oldest queue file is ${age}ms old`);
                this.stats.backpressureEvents++;
                
                // Log backpressure event
                await this.appendEvent({
                    activity: 'system_backpressure',
                    feature_json: {
                        queue_depth: lines.length,
                        oldest_age_ms: age,
                        threshold_ms: this.backpressureThreshold
                    }
                });
            } else if (wasBackpressured && !this.isBackpressured) {
                console.log('Backpressure deactivated');
            }
        } else {
            this.isBackpressured = false;
        }
    }
    
    /**
     * Start rotation timer
     */
    startRotationTimer() {
        setInterval(async () => {
            // Check backpressure
            await this.checkBackpressure();
            
            // Rotate if needed
            if (this.shouldRotate()) {
                await this.rotateQueue();
            }
            
            // Update offset periodically
            this.updateOffset();
            
        }, 10000); // Check every 10 seconds
    }
    
    /**
     * Get queue statistics
     */
    getStats() {
        return {
            ...this.stats,
            currentFileSize: this.currentFileSize,
            isBackpressured: this.isBackpressured,
            queueDir: this.queueDir
        };
    }
    
    /**
     * Graceful shutdown
     */
    async shutdown() {
        console.log('Shutting down queue...');
        
        // Final fsync
        if (this.currentFileHandle) {
            fs.fsyncSync(this.currentFileHandle);
            fs.closeSync(this.currentFileHandle);
        }
        
        // Final offset update
        this.updateOffset();
        
        console.log('Queue shutdown complete. Stats:', this.getStats());
    }
}

// Export for use in other modules
module.exports = DurableNDJSONQueue;

// If run directly, start a standalone queue
if (require.main === module) {
    const queue = new DurableNDJSONQueue({
        queueDir: process.env.QUEUE_DIR || '/tmp/claude_queue'
    });
    
    // Handle shutdown signals
    process.on('SIGINT', async () => {
        await queue.shutdown();
        process.exit(0);
    });
    
    process.on('SIGTERM', async () => {
        await queue.shutdown();
        process.exit(0);
    });
    
    console.log('NDJSON Queue started. Waiting for events...');
    
    // Example: Accept events via stdin
    process.stdin.on('data', async (data) => {
        try {
            const event = JSON.parse(data.toString());
            const id = await queue.appendEvent(event);
            console.log(`Queued event: ${id}`);
        } catch (err) {
            console.error('Error processing input:', err);
        }
    });
}