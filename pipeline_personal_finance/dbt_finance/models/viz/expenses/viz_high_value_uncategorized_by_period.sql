WITH params AS (
  SELECT {{ var('high_value_threshold', 1000) }}::numeric AS threshold
),

uncategorized_base AS (
  SELECT 
    ft.transaction_date,
    ft.transaction_amount,
    ABS(ft.transaction_amount)::numeric AS amount_abs,
    -- carry both description and memo for flexible normalization
    ft.transaction_description,
    ft.transaction_memo,
    ft.account_key
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  WHERE dc.category = 'Uncategorized'
    AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
    AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 1
),

uncategorized_norm AS (
  SELECT 
    transaction_date,
    amount_abs,
    transaction_memo,
    transaction_description,
    -- Normalize using description if present, else memo; strip receipts/dates/cards and numbers
    UPPER(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(COALESCE(transaction_description, transaction_memo), 'Receipt\\s+[0-9]+', ' ', 'gi'),
            'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', ' ', 'gi'
          ),
          'Card\\s+[\\dx]+' , ' ', 'gi'
        ),
        '[^A-Za-z]+' , ' ', 'g'
      )
    ) AS memo_norm,
    account_key
  FROM uncategorized_base
),

-- Aggregate by period (month/quarter/year), memo, and account
uncategorized_period_agg AS (
  SELECT 'month'::text AS period_type,
         (DATE_TRUNC('month', transaction_date))::date AS period_start,
         account_key,
         memo_norm,
         -- Use description if present, else memo for example text
         MIN(COALESCE(transaction_description, transaction_memo)) AS sample_memo,
         COUNT(*) AS txn_count,
         SUM(amount_abs) AS total_amount_abs
  FROM uncategorized_norm
  GROUP BY 1,2,3,4
  UNION ALL
  SELECT 'quarter'::text AS period_type,
         (DATE_TRUNC('quarter', transaction_date))::date AS period_start,
         account_key,
         memo_norm,
         MIN(COALESCE(transaction_description, transaction_memo)) AS sample_memo,
         COUNT(*) AS txn_count,
         SUM(amount_abs) AS total_amount_abs
  FROM uncategorized_norm
  GROUP BY 1,2,3,4
  UNION ALL
  SELECT 'year'::text AS period_type,
         (DATE_TRUNC('year', transaction_date))::date AS period_start,
         account_key,
         memo_norm,
         MIN(COALESCE(transaction_description, transaction_memo)) AS sample_memo,
         COUNT(*) AS txn_count,
         SUM(amount_abs) AS total_amount_abs
  FROM uncategorized_norm
  GROUP BY 1,2,3,4
),

high_value_uncategorized AS (
  SELECT 
    upa.*,
    da.account_name
  FROM uncategorized_period_agg upa
  JOIN {{ ref('dim_accounts') }} da
    ON da.account_key = upa.account_key
  WHERE upa.total_amount_abs > (SELECT threshold FROM params)
),

-- Build memo-based suggestions from already categorized transactions (cross-account)
categorized_base AS (
  SELECT 
    UPPER(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(COALESCE(ft.transaction_description, ft.transaction_memo), 'Receipt\\s+[0-9]+', ' ', 'gi'),
            'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', ' ', 'gi'
          ),
          'Card\\s+[\\dx]+' , ' ', 'gi'
        ),
        '[^A-Za-z]+' , ' ', 'g'
      )
    ) AS memo_norm,
    dc.category,
    dc.subcategory,
    dc.store,
    dc.internal_indicator,
    COUNT(*) AS support_count
  FROM {{ ref('fct_transactions') }} ft
  JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  WHERE dc.category <> 'Uncategorized'
    AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
    AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 1
  GROUP BY 1,2,3,4,5
),

categorized_totals AS (
  SELECT memo_norm, SUM(support_count) AS total_support
  FROM categorized_base
  GROUP BY 1
),

categorized_ranked AS (
  SELECT 
    cb.*,
    ct.total_support,
    (cb.support_count::numeric / NULLIF(ct.total_support, 0)) AS confidence,
    ROW_NUMBER() OVER (
      PARTITION BY cb.memo_norm
      ORDER BY cb.support_count DESC, cb.category, cb.subcategory, cb.store
    ) AS rnk
  FROM categorized_base cb
  JOIN categorized_totals ct
    ON ct.memo_norm = cb.memo_norm
),

best_memo_suggestion AS (
  SELECT *
  FROM categorized_ranked
  WHERE rnk = 1
),

-- Token-based fuzzy matching between high-value uncategorized and categorized memos
stopwords AS (
  SELECT unnest(ARRAY[
    'THE','TO','FROM','PAYMENT','TRANSFER','DEBIT','CREDIT','CARD','DATE','RECEIPT','IN','OF','AND','AT','ONLINE','PURCHASE','DIRECT','ORDER','AUTOPAY','MONTHLY','SERVICE','FEE','INTEREST','BANK','TRANSACTION','VISA','EFTPOS','WITHDRAWAL','NETT','ADVANCE'
  ]) AS sw
),

hvu_memos AS (
  SELECT DISTINCT memo_norm FROM high_value_uncategorized
),

uncat_tokens AS (
  SELECT 
    u.memo_norm AS uncat_memo_norm,
    tok AS token
  FROM hvu_memos u
  {% if target.type == 'duckdb' %}
  CROSS JOIN UNNEST(regexp_split_to_array(u.memo_norm, '\\s+')) AS tok(tok)
  {% else %}
  CROSS JOIN LATERAL regexp_split_to_table(u.memo_norm, '\\s+') AS tok
  {% endif %}
  WHERE length(tok) >= 3
    AND tok ~ '[A-Z]+'
    AND tok NOT IN (SELECT sw FROM stopwords)
),

cat_tokens AS (
  SELECT 
    cb.memo_norm AS cat_memo_norm,
    tok AS token
  FROM categorized_base cb
  {% if target.type == 'duckdb' %}
  CROSS JOIN UNNEST(regexp_split_to_array(cb.memo_norm, '\\s+')) AS tok(tok)
  {% else %}
  CROSS JOIN LATERAL regexp_split_to_table(cb.memo_norm, '\\s+') AS tok
  {% endif %}
  WHERE length(tok) >= 3
    AND tok ~ '[A-Z]+'
    AND tok NOT IN (SELECT sw FROM stopwords)
),

uncat_sizes AS (
  SELECT uncat_memo_norm, COUNT(DISTINCT token) AS uncat_sz
  FROM uncat_tokens
  GROUP BY 1
),

cat_sizes AS (
  SELECT cat_memo_norm, COUNT(DISTINCT token) AS cat_sz
  FROM cat_tokens
  GROUP BY 1
),

pairwise_overlap AS (
  SELECT 
    u.uncat_memo_norm,
    c.cat_memo_norm,
    COUNT(DISTINCT u.token) AS overlap_count
  FROM uncat_tokens u
  JOIN cat_tokens c ON c.token = u.token
  GROUP BY 1,2
),

pairwise_scored AS (
  SELECT 
    o.uncat_memo_norm,
    o.cat_memo_norm,
    o.overlap_count,
    us.uncat_sz,
    cs.cat_sz,
    (o.overlap_count::numeric / NULLIF(us.uncat_sz + cs.cat_sz - o.overlap_count, 0)) AS jaccard
  FROM pairwise_overlap o
  JOIN uncat_sizes us ON us.uncat_memo_norm = o.uncat_memo_norm
  JOIN cat_sizes cs ON cs.cat_memo_norm = o.cat_memo_norm
),

pairwise_best AS (
  SELECT * FROM (
    SELECT 
      ps.*,
      ROW_NUMBER() OVER (
        PARTITION BY ps.uncat_memo_norm
        ORDER BY ps.jaccard DESC NULLS LAST, ps.overlap_count DESC
      ) AS rnk
    FROM pairwise_scored ps
  ) ranked
  WHERE rnk = 1
)

SELECT 
  hvu.period_type,
  hvu.period_start,
  hvu.account_key,
  hvu.account_name,
  hvu.memo_norm,
  hvu.sample_memo,
  hvu.txn_count,
  hvu.total_amount_abs,
  bms.category            AS suggested_category,
  bms.subcategory         AS suggested_subcategory,
  bms.store               AS suggested_store,
  bms.internal_indicator  AS suggested_internal_indicator,
  bms.support_count,
  bms.total_support,
  bms.confidence
FROM high_value_uncategorized hvu
LEFT JOIN pairwise_best pb
  ON pb.uncat_memo_norm = hvu.memo_norm
LEFT JOIN best_memo_suggestion bms
  ON bms.memo_norm  = COALESCE(pb.cat_memo_norm, hvu.memo_norm)
ORDER BY hvu.period_type, hvu.period_start, hvu.account_name, hvu.total_amount_abs DESC
