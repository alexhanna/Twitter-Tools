CREATE TABLE firehose_queue (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
json                      TEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE candidate_queue (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
username                  VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE username_id (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
username                  VARCHAR(255) NOT NULL,
user_id                   INT UNSIGNED NOT NULL,
UNIQUE(username),
UNIQUE(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE follow (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
user_id                   INT UNSIGNED NOT NULL,
is_candidate              TINYINT NOT NULL,
date_created              DATE NOT NULL,
UNIQUE(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE follow_sample (
user_id                   INT UNSIGNED NOT NULL,
UNIQUE(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE relation (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
user1                     INT UNSIGNED NOT NULL,
user2                     INT UNSIGNED NOT NULL,
date_created              DATE NOT NULL,
INDEX(user1),
INDEX(user2),
UNIQUE(user1, user2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE twit_options (
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
option_key                VARCHAR(255) NOT NULL,
option_value              VARCHAR(255) NOT NULL,
UNIQUE(option_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

