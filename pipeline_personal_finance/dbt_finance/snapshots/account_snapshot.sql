{% snapshot account_snapshot %}

{{
    config(
      target_schema='snapshots',
      unique_key='account_key',
      strategy='timestamp',
      updated_at='updated_at'
    )
}}

select * from {{ ref('dim_accounts') }}

{% endsnapshot %}
