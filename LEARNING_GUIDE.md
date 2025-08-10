# 🎓 Learn ActivitySchema by Tracking Your Claude Usage

## The Beautiful Recursive Loop

Welcome to a unique learning experience where you'll master the ActivitySchema pattern by implementing it for your own Claude Code usage, then using Claude to analyze and improve it!

```
You use Claude Code → Your usage gets logged → You query your usage 
    ↓                                               ↓
You improve logging ← Claude helps you analyze ← You find patterns
```

## 🚀 Quick Start (2 minutes)

```bash
# 1. Enable logging for this project
echo "json" > .claude-log

# 2. Check your learning dashboard
./bin/my-claude-journey

# 3. Start the interactive tutorial
./bin/teach-me-activityschema
```

## 📚 The Learning Path

### Week 1: Discovery Challenge - "Find the Orphaned Sessions"

**The Problem**: Most sessions don't have clean end events. Why?

```sql
-- Run this query to discover the issue
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_LEARNING_ORPHANED_SESSIONS;
```

**Learning Points**:
- Real-world systems have messy data
- Users hit Ctrl+C, connections drop, processes crash
- Resilient design requires handling incomplete data

**Your Task**: 
1. Find your own orphaned sessions
2. Propose a solution (heartbeats? timeouts? graceful shutdown?)
3. Use Claude to help design the fix!

### Week 2: Enhancement Challenge - "Add Tool Tracking"

**Current State**: We only log session start/end
**Goal**: Detect and log individual tool usage (bash, file operations, etc.)

```bash
# Hint: Claude's output contains patterns like:
# "Running tool: Bash"
# "Reading file: /path/to/file"

# Challenge: Update the wrapper to detect these
```

**Learning Points**:
- Pattern matching in streams
- Real-time event extraction
- Balancing completeness vs performance

### Week 3: Analysis Challenge - "Calculate Real Costs"

**Current State**: Token estimates are rough guesses
**Goal**: Accurate cost tracking

```sql
-- Current "cost" calculation is fantasy
SELECT * FROM CLAUDE_LOGS.ACTIVITIES.V_COST_LEARNING;

-- Challenge: Research actual Claude pricing and fix this
```

**Learning Points**:
- Token counting algorithms
- Cost allocation patterns
- Business metrics in technical systems

### Week 4: Meta Challenge - "Query Your Learning"

**The Ultimate Test**: Use Claude to analyze how you've been learning!

```sql
-- Find sessions where you studied the system itself
WITH recursive_learning AS (
    SELECT 
        customer as session_id,
        ts,
        feature_json:project_path::STRING as project
    FROM ACTIVITY_STREAM
    WHERE project LIKE '%snowflake-activity-schema%'
        AND activity = 'claude_session_start'
)
SELECT 
    DATE(ts) as day,
    COUNT(*) as meta_sessions,
    'You used Claude to study Claude!' as insight
FROM recursive_learning
GROUP BY DATE(ts);
```

## 🔍 Key Queries for Learning

### 1. Your Personal Dashboard
```sql
-- See your complete learning journey
SELECT * FROM V_META_LEARNING 
WHERE your_session_marker = '👉 YOU ARE HERE';
```

### 2. System Evolution
```sql
-- Watch the system grow as we add features
SELECT * FROM V_SYSTEM_EVOLUTION
ORDER BY day DESC;
```

### 3. Pattern Discovery
```sql
-- Find usage patterns
SELECT * FROM V_PATTERN_DISCOVERY
WHERE hour_of_day BETWEEN 9 AND 17;  -- Business hours
```

### 4. The Orphan Problem
```sql
-- Understand incomplete data
SELECT * FROM V_LEARNING_ORPHANED_SESSIONS;
```

## 💡 Learning Exercises

### Exercise 1: Fix the Orphan Problem
```sql
-- Write a query that identifies sessions that likely crashed
-- Hint: Sessions with only a start event and > 1 hour old
```

### Exercise 2: Detect Power Users
```sql
-- Who uses Claude the most?
-- Hint: GROUP BY anonymous_customer_id
```

### Exercise 3: Cost Attribution
```sql
-- Allocate costs to projects
-- Hint: JOIN with project_path
```

## 🏆 Achievements to Unlock

- [ ] **First Query**: Run your first SELECT on ACTIVITY_STREAM
- [ ] **Orphan Hunter**: Identify the orphaned sessions problem
- [ ] **Meta-Learner**: Query your own Claude usage
- [ ] **Pattern Finder**: Discover a usage pattern
- [ ] **System Improver**: Submit an improvement to the logging
- [ ] **Teacher**: Help someone else learn ActivitySchema
- [ ] **Recursive Master**: Use Claude to analyze Claude analyzing Claude

## 🛠️ How the System Works

### Components

1. **`.claude-log` file**: Triggers logging (intentional friction for learning)
2. **Wrapper scripts**: Intercept Claude execution
3. **Activity logging**: Writes to Snowflake
4. **Learning views**: Designed to teach, not just display data

### The Pedagogical Design

**Intentional Imperfections**:
- Orphaned sessions → Teaches resilience
- Manual .claude-log → Teaches explicit consent
- Simple logging → Teaches iterative improvement
- Visible failures → Teaches debugging

## 📈 Your Learning Metrics

Track your progress with this query:

```sql
WITH your_progress AS (
    SELECT 
        COUNT(DISTINCT DATE(ts)) as days_active,
        COUNT(DISTINCT customer) as sessions_started,
        SUM(CASE 
            WHEN feature_json:project_path::STRING LIKE '%snowflake-activity%' 
            THEN 1 ELSE 0 
        END) as meta_sessions,
        MAX(ts) as last_active
    FROM ACTIVITY_STREAM
    WHERE anonymous_customer_id = SYSTEM$CLIENT_HOST()
)
SELECT 
    days_active,
    sessions_started,
    meta_sessions,
    CASE 
        WHEN meta_sessions > 10 THEN '🏆 ActivitySchema Expert!'
        WHEN meta_sessions > 5 THEN '📈 Advanced Learner'
        WHEN sessions_started > 5 THEN '🌱 Growing Knowledge'
        WHEN sessions_started > 0 THEN '🚀 Just Starting'
        ELSE '👋 Ready to Begin!'
    END as your_level,
    'Next: Use Claude to improve the logging!' as next_challenge
FROM your_progress;
```

## 🤝 Collaborative Learning

### Share Your Discoveries

Found something interesting? Share it!

```sql
-- Add your insight as a comment in the view
COMMENT ON VIEW V_MY_INSIGHT IS 'I discovered that...';
```

### Weekly Challenges

**Week 1**: Most orphaned sessions
**Week 2**: Most creative query  
**Week 3**: Best improvement PR
**Week 4**: Teaching someone else

## 🔄 The Meta-Learning Loop

The beauty of this system is its recursive nature:

1. **Level 1**: Use Claude normally
2. **Level 2**: Query your Claude usage
3. **Level 3**: Use Claude to analyze the queries
4. **Level 4**: Use Claude to improve the analysis
5. **Level ∞**: It's Claude all the way down!

## 📝 Assignment: Your First PR

After a week of learning, submit an improvement:

1. Identify a gap in the logging
2. Use Claude to help design a solution
3. Implement it (with Claude's help)
4. Submit a PR
5. Your improvement becomes part of the curriculum!

## 🎯 Success Criteria

You've mastered ActivitySchema when you can:

- [ ] Explain why sessions get orphaned
- [ ] Write queries to find patterns in event data  
- [ ] Design resilient event schemas
- [ ] Use the system to improve itself
- [ ] Teach someone else these concepts

## 🚦 Getting Help

```bash
# Check your status
./bin/my-claude-journey

# Run the tutorial
./bin/teach-me-activityschema

# Ask Claude for help
claude -p "Help me understand the orphaned sessions in ActivitySchema"
# This query itself gets logged - meta!
```

## 🎉 Remember

**The bugs are features** - they're learning opportunities!
**The workarounds are lessons** - they teach resilience!
**The imperfections are pedagogical** - they spark improvement!

Happy learning! 🎓