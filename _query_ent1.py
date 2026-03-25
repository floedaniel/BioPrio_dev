import sqlite3
import json

conn = sqlite3.connect('databases/clean_database/clean.db')
conn.row_factory = sqlite3.Row
cur = conn.cursor()
cur.execute("SELECT * FROM questions WHERE idQuestion = 'ENT1'")
row = cur.fetchone()
if row:
    print("=== ENT1 Question Details ===\n")
    for key in row.keys():
        value = row[key]
        if key == 'list':
            print(f"{key}:")
            try:
                parsed = json.loads(value)
                print(json.dumps(parsed, indent=2))
            except:
                print(value)
        else:
            print(f"{key}: {value}")
        print()
conn.close()
