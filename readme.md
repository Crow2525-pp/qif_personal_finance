# Introduction
- Use granfana to display finance information on a home assistant dashboard for wife & I to access
- Deploy on a home server and update QIF files (manually/periodically) to gain financial insights.

# Installation
1. ensure that docker is installed and running (windows)
2. replace sample.env with a .env and update with your own credentials
3. download qif files from bank and add them in pipeline_personal_finance\qif_files
4. run docker-compose up -d and then goto localhost:3000
5. reload the definitions and then run the asset.
6. [TBC]