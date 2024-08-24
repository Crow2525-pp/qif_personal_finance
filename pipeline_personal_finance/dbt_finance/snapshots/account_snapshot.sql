{% snapshot account_snapshot %}

{{
    config(
      target_schema='snapshots',
      unique_key='surrogate_key',
      strategy='timestamp',
      updated_at='end_date'
    )
}}

select * from {{ ref('dim_account') }}

{% endsnapshot %}
