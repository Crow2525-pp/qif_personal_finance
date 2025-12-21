import os

from dagster import Definitions, EnvVar
from dotenv import load_dotenv

from .resources import SqlAlchemyClientResource
from .assets import finance_dbt_assets, upload_dataframe_to_database

load_dotenv()

resources = {
    "personal_finance_database": SqlAlchemyClientResource(
            drivername="postgresql+psycopg2",
            username=EnvVar("DAGSTER_POSTGRES_USER"),
            password=EnvVar("DAGSTER_POSTGRES_PASSWORD"),
            host=EnvVar("DAGSTER_POSTGRES_HOST"),
            port=int(os.getenv("DAGSTER_POSTGRES_PORT", "5432")),
            database=EnvVar("DAGSTER_POSTGRES_DB"),)
}

defs = Definitions(
    assets=[finance_dbt_assets, upload_dataframe_to_database],
    resources=resources[deployment_name],
    # jobs=[all_asset_job],
)

#
# @sensor(job=all_asset_job)
# def my_directory_sensor():
#     for filename in os.listdir(QIF_FILES):
#         filepath = os.path.join(QIF_FILES, filename)
#         if os.path.isfile(filepath):
#             yield RunRequest(
#                 run_key=filename,
#                 run_config=RunConfig(
#                 ),
#             )
