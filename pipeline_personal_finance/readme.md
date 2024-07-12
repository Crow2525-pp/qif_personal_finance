# Personal Finance Dashboard

## Plan
- Use granfana to display finance information on a home assistant dashboard for wife & I to access
- [x] Use postgres server to store banking data
- [x] Use dbt to transform the data into workable metrics
- [x] Use dagster to orchestrate the qif -> postgres and dbt       transformations
- [x] Use Docker to run the project from docker server at home
- [ ] Upload Docker to Home Server


## Todo
 - Get docker compose files working
 - Adjust QIF ingestor to allow for any name of qif file.
 - Adjust DBT to allow for any name/quantity of account number


## Usage
- add qif files to the qif_files
- update .env file
- add seed files for name of accounts and known balances at known dates (choose a date where there is only one transaction on the date)
- run docker-compose up -d.
