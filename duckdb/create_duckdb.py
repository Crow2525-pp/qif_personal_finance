import os
import duckdb

# Determine the directory of the script being run
script_directory = os.path.dirname(os.path.abspath(__file__))
database_path = os.path.join(script_directory, 'finance.duckdb')

# Check if the database file already exists
if os.path.exists(database_path):
    raise Exception("Database 'finance.duckdb' already exists.")

# Connect to the database (it will be created since it doesn't exist)
conn = duckdb.connect(database_path)

# Create a new schema named 'raw'
conn.execute('CREATE SCHEMA IF NOT EXISTS raw')

# Commit the changes to ensure the schema is created
conn.commit()

# Disconnect from the database
conn.close()
