CREATE TABLE static_userinfo (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
user_id                   INT UNSIGNED NOT NULL,
created_at                DATETIME NOT NULL,
UNIQUE(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE tweet (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
status_id                 BIGINT UNSIGNED NOT NULL,
user_id                   INT UNSIGNED NOT NULL,
text                      VARCHAR(255) NOT NULL,
geo                       VARCHAR(255),
source                    VARCHAR(255),
retweet_id                BIGINT UNSIGNED,
in_reply_to_status_id     BIGINT UNSIGNED,
in_reply_to_user_id       INT UNSIGNED,
created_at                DATETIME NOT NULL,
INDEX(in_reply_to_user_id),
UNIQUE(status_id),
FOREIGN KEY (user_id)
  REFERENCES static_userinfo (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE delete_tweet (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
status_id                 BIGINT UNSIGNED NOT NULL,
user_id                   INT UNSIGNED NOT NULL,
UNIQUE(status_id, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE tweet_userinfo (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
status_id                 BIGINT UNSIGNED NOT NULL,
name                      VARCHAR(32) NOT NULL,
screen_name               VARCHAR(32) NOT NULL,
description               VARCHAR(255),
profile_image_url         VARCHAR(255),
url                       VARCHAR(255),
location                  VARCHAR(255),
time_zone                 VARCHAR(32),
lang                      VARCHAR(12),
user_id                   INT UNSIGNED NOT NULL,
followers_count           INT UNSIGNED NOT NULL,
friends_count             INT UNSIGNED NOT NULL,
statuses_count            INT UNSIGNED NOT NULL,
listed_count              INT UNSIGNED NOT NULL,
FOREIGN KEY (status_id)
  REFERENCES tweet (status_id),
FOREIGN KEY (user_id)
  REFERENCES static_userinfo (user_id),
UNIQUE(status_id),
INDEX(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE tweet_entity (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
status_id                 BIGINT UNSIGNED NOT NULL,
type                      VARCHAR(24) NOT NULL,
value                     VARCHAR(255) NOT NULL,
INDEX(status_id),
FOREIGN KEY (status_id)
  REFERENCES tweet (status_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
