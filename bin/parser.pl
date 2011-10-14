#!/usr/bin/perl
# 
# Twitter status parser, v1
# Author: Alexander Hanna
# Email: alex.hanna@gmail.com
#
# September-October 2010

use strict;
use warnings;

use DBI;
use Data::Dumper;
use DateTime::Format::Strptime;
use JSON::XS;
################################################################################

## raw data
my($r_dbname) = '';
my($r_dbuser) = '';
my($r_dbpass) = '';
my($r_dbhost) = '';

## analysis
my($s_dbname) = '';
my($s_dbuser) = '';
my($s_dbpass) = '';
my($s_dbhost) = '';

my($dbh_r) = DBI->connect("DBI:mysql:database=$r_dbname;hostname=$r_dbhost;port=3306", 
                        $r_dbuser, 
                        $r_dbpass,                                               
                        {
                            AutoCommit => 0
                        }) or die $DBI::errstr;

my($dbh_s) = DBI->connect("DBI:mysql:database=$s_dbname;hostname=$s_dbhost;port=3306", 
                          $s_dbuser, 
                          $s_dbpass,
                          {
                              AutoCommit => 0
                          }) or die $DBI::errstr;

my $strp = new DateTime::Format::Strptime(
    pattern     => '%a %b %d %T +0000 %Y',
    locale      => 'en_US',
    time_zone   => 'GMT');

my($deleted) = 0;
my($added)   = 0;

my(%users)    = ();
my(%statuses) = ();

sub insertTweet {
    my($json, $rt) = @_; 

    ## process retweet if it is not null
    my $retweet_id = undef;
    if ($json->{retweeted_status}) { 
        insertTweet($json->{retweeted_status}, 1);
        $retweet_id = $json->{retweeted_status}->{id};
    }

    ## already in the database; RT
    return $json->{id} if $statuses{$json->{id}};
              
## userinfo
=pod
user_id                   INT UNSIGNED NOT NULL,
created_at                DATETIME NOT NULL
=cut
 
    eval {   
        my($user) = $json->{user};
 
        unless ($users{$user->{id}}) {
            my(@userinfo)   = qw/id/;
            my($created_at) = $strp->parse_datetime($user->{created_at}) if $user->{created_at};
            
            my($sql)  = "INSERT INTO static_userinfo (user_id, created_at) VALUES (?,?)";
            my($sth)  = $dbh_s->prepare($sql);
        
            my(@bind) = map { $user->{$_} } @userinfo;
            push @bind, $created_at;
        
            if ($sth->execute( @bind )) {
                $users{$user->{id}} = 1;
            }
        }
        
## tweet
=pod
status_id                 INT UNSIGNED NOT NULL,
user_id                   INT UNSIGNED NOT NULL,
text                      VARCHAR(255) NOT NULL,
geo                       VARCHAR(255),
source                    VARCHAR(32),
retweet_id                INT UNSIGNED,
in_reply_to_status_id     INT UNSIGNED,
in_reply_to_user_id       INT UNSIGNED,
created_at                DATETIME NOT NULL,
FOREIGN KEY (user_id)
  REFERENCES userinfo (user_id)
=cut
    
        my(@tweetinfo) = qw/id text source in_reply_to_status_id in_reply_to_user_id/;
        my($created_at)    = $strp->parse_datetime($json->{created_at}) if $json->{created_at};
        
        my($geo) = $json->{geo} ? ( join ',', @{ $json->{geo}->{coordinates} } ) : undef;
        my($fav) = $json->{favorited} ? 1 : 0;
        
        my($sql) = "INSERT INTO tweet (status_id, text, source, " . 
            "in_reply_to_status_id, in_reply_to_user_id, user_id, " .
            "geo, retweet_id, created_at) VALUES (?,?,?, ?,?,?, ?,?,?)";
        my($sth) = $dbh_s->prepare($sql);
        
        my(@bind) = map { $json->{$_} } @tweetinfo;
        push @bind, $user->{id}, $geo, $retweet_id, $created_at;
        $sth->execute( @bind );
        
## tweet_userinfo
=pod
user_id                   INT UNSIGNED NOT NULL,
status_id                 INT UNSIGNED NOT NULL,
name                      VARCHAR(32) NOT NULL,
screen_name               VARCHAR(32) NOT NULL,
description               VARCHAR(255),
profile_image_url         VARCHAR(255),
url                       VARCHAR(255),
location                  VARCHAR(255),
time_zone                 VARCHAR(32),
lang                      VARCHAR(12),
followers_count           INT UNSIGNED NOT NULL,
friends_count             INT UNSIGNED NOT NULL,
statuses_count            INT UNSIGNED NOT NULL,
listed_count              INT UNSIGNED NOT NULL,
FOREIGN KEY (status_id)
  REFERENCES tweet (status_id),
FOREIGN KEY (user_id)
  REFERENCES userinfo (user_id),
UNIQUE(status_id),
INDEX(user_id)
=cut

        ## time and tweet specific user info
        my(@tweetuserinfo) = qw/name screen_name description
                               profile_image_url url location
                               time_zone lang followers_count 
                               friends_count statuses_count listed_count/;

        $sql = "INSERT INTO tweet_userinfo (" .
            "name, screen_name, description, " . 
            "profile_image_url, url, location," . 
            "time_zone, lang, followers_count, " .
            "friends_count, statuses_count, listed_count, " .
            "user_id, status_id) " .
            "VALUES (?,?,?, ?,?,?, ?,?,?, ?,?,?, ?,?)";
        $sth = $dbh_s->prepare($sql);
        
        @bind = map { $user->{$_} ? $user->{$_} : '' } @tweetuserinfo;

        push @bind, $user->{id}, $json->{id};
        $sth->execute( @bind );
        
## tweet_entity
=pod
id                        INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
status_id                  INT UNSIGNED NOT NULL,
type                      VARCHAR(24) NOT NULL,
value                     VARCHAR(255) NOT NULL,
FOREIGN KEY (status_id)
  REFERENCES tweet (status_id)
=cut

        my(@hts)  = $json->{entities}->{hashtags} ? @{ $json->{entities}->{hashtags} } : ();
        my(@ums)  = $json->{entities}->{user_mentions} ? @{ $json->{entities}->{user_mentions} } : ();
        my(@urls) = $json->{entities}->{urls} ? @{ $json->{entities}->{urls} } : ();
        
        if ( scalar(@hts) || scalar(@ums) || scalar(@urls) ) {
            my($entities) = 0;
            @bind = ();
            
            foreach my $ht (@hts) {
                push @bind, $json->{id}, 'hashtag', $ht->{text};
                $entities++;
            }
            
            foreach my $um (@ums) {
                push @bind, $json->{id}, 'user_mention', $um->{id};
                $entities++;
            }
            
            foreach my $url (@urls) {
                push @bind, $json->{id}, 'url', $url->{url};
                $entities++;
            }
            
            my(@str) = ();
            while( $entities ) {
                push @str, '(?,?,?)';
                $entities--;
            }
            
            $sql = "INSERT INTO tweet_entity (status_id, type, value) VALUES " . ( join ',', @str );
            $sth = $dbh_s->prepare($sql);
            $sth->execute(@bind);
        }
        
        $dbh_s->commit();
        $added++;
        $statuses{$json->{id}} = 1;
        
        return $json->{id};
    };
    if ($@) {
        warn "Couldn't add ", $json->{id}, "\t", $@, "\n";
        $dbh_s->rollback();
        return 0;
    } 
}

sub main {
    print "Loading userinfo...", "\n";
    my($sql) = 'SELECT user_id FROM static_userinfo';
    my($sth) = $dbh_s->prepare($sql);
    $sth->execute();    

    while(my($user) = $sth->fetchrow_array()) {
        $users{$user} = 1;
    }

    print "Loading existing tweets...", "\n";
    $sql = 'SELECT status_id FROM tweet';
    $sth = $dbh_s->prepare($sql);
    $sth->execute();

    while(my($status) = $sth->fetchrow_array()) {
        $statuses{$status} = 1;
    }

    ## put lines that do not pass json eval in this file and reprocess
    ## fixme: make sure that all of json eval happens in this file
    open(my $fh, '>>', 'json_errors.json');

    my($start) = 0;
    my($limit) = 1000;
    for (my $i = $start; ;$i = $i + $limit) { 
        print $i, "\n";

        $sql      = "SELECT json FROM firehose_queue WHERE id > ? AND id <= ?";
        my($sth2) =  $dbh_r->prepare($sql);
        $sth2->execute( $i , $i + $limit );

        ## if nothing is returned, then sleep and wait for more tweets to accrue
        unless ($sth2->rows()) {
            print "Sleeping...", "\n";
            sleep(3600);            
        } else {
            while(my($tweet) = $sth2->fetchrow_array()) {
                chomp $tweet;
                
                next() unless $tweet;
                next() if $tweet =~ m/^\s+$/;
                
                my($json)    = undef;
                eval {
                    $json = decode_json($tweet);
                };
                if ($@) {
                    warn $@;
                    print $fh $tweet;
                    print $fh "\n";
                    next();
                }
                
                unless ($json->{delete}) {
                    next() if $statuses{$json->{id}};
                    insertTweet($json, 0);
                    print $added, "\n";
                } else {   
                    $sql = "INSERT INTO delete_tweet (status_id, user_id) VALUES (?,?)";
                    $sth = $dbh_s->prepare($sql);
                    $sth->execute($json->{delete}->{status}->{id}, $json->{delete}->{status}->{user_id});        
                    $deleted++;
                }
            }    
        }
    }
}

main();
    
__END__
