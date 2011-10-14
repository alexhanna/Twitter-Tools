SELECT
    t.status_id  AS "Tweet ID",
    t.text       AS "Text",
    t.geo        AS "Geolocation",
    t.source     AS "Source",
    t.retweet_id AS "Retweeted Tweet ID",
    t.created_at AS "Created at",
    
    t.user_id     AS "User ID",
    u.screen_name AS "Screen Name",
    u.name        AS "Name",
    u.description AS "User Description",
    u.url         AS "User URL",
    u.lang        AS "User Language",
    u.time_zone   AS "User Timezone",
    s.created_at  AS "User Created At",

    u.followers_count AS "User Follow Count",
    u.friends_count   AS "User Followee Count",
    u.statuses_count  AS "User Status Count"
    
      FROM tweet t
INNER JOIN tweet_userinfo  u ON (t.status_id = u.status_id)
INNER JOIN static_userinfo s ON (t.user_id   = s.user_id)
