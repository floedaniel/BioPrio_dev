const sqlite3 = require('better-sqlite3');
const path = require('path');

const dbPath = path.join(__dirname, 'databases', 'clean_database', 'clean.db');
const db = new sqlite3(dbPath);

const row = db.prepare("SELECT * FROM questions WHERE idQuestion = 'ENT1'").get();
if (row) {
    console.log("=== ENT1 Question Details ===\n");
    for (const [key, value] of Object.entries(row)) {
        console.log(`${key}:`);
        if (key === 'list') {
            try {
                const parsed = JSON.parse(value);
                console.log(JSON.stringify(parsed, null, 2));
            } catch (e) {
                console.log(value);
            }
        } else {
            console.log(value);
        }
        console.log();
    }
}
db.close();
