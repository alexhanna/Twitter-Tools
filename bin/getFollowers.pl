#!/usr/bin/perl
# 
# Update followers
# Author: Alexander Hanna
# Email: ahanna@ssc.wisc.edu
#
# June 2010

use strict;
use warnings;

use DBI;
use Data::Dumper;
use HTTP::Request::Common;
use JSON;
use LWP::UserAgent;
use Net::Twitter;
use WWW::Mechanize;
################################################################################

# Twitter Credentials
my($username) = '';
my($password) = '';

# OAuth
my($consumer_secret) = '';
my($consumer_key)    = '';

my($access_token)        = ''; 
my($access_token_secret) = ''; 

my($dbname, $dbhost, $dbuser, $dbpass) = ();

# db info
my($dbh) = DBI->connect('DBI:mysql:database=$dbname;hostname=$dbhost;port=3306', 
                        $dbuser,
                        $dbpass) or die $DBI::errstr;

my $ua   = LWP::UserAgent->new();
my $mech = WWW::Mechanize->new();
my $nt   = Net::Twitter->new(
    traits          => [qw/API::REST OAuth RateLimit/],
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret
    );

my(%stored_users)  = ();
my(%stored_cands)  = ();
my(%invalid_users) = ();
my(%username_id)   = ();

my(%stored_relations) = (); 

sub addUser {
    my($user_id, $is_candidate) = @_;

    my($sql) = "INSERT INTO follow (user_id, is_candidate, date_created) VALUES (?, ?, DATE(NOW()))";
    my($sth) = $dbh->prepare($sql);

    if ($sth->execute($user_id, $is_candidate)) {
        $stored_users{$user_id} = 1;
        return 1;
    }

    return 0;
}

sub updateUser {
    my($user_id, $is_candidate) = @_;
    
    my($sql) = "UPDATE follow SET is_candidate = ? WHERE user_id = ?";
    my($sth) = $dbh->prepare($sql);
    
    if ($sth->execute($is_candidate, $user_id)) {
        return 1;
    }
    
    return 0;
}

sub addRelation {
    my($user1, $user2) = @_;

    my($sql) = "INSERT INTO relation (user1, user2, date_created) VALUES (?, ?, DATE(NOW()))";
    my($sth) = $dbh->prepare($sql);

    if ($sth->execute($user1, $user2)) {
        $stored_relations{$user1 . '-' . $user2} = 1;
        return 1;
    }
    
    return 0;
}

sub checkAuth {
    unless ( $nt->authorized() ) {
        # The client is not yet authorized: Do it now
        print "Authorize this app at ", $nt->get_authorization_url, " and enter the PIN#\n";
        
        my $pin = <STDIN>; # wait for input
        chomp $pin;

        ## store access tokens
        my(@t) = $nt->request_access_token(verifier => $pin);
        save_tokens($t[0], $t[1]);
    }
}

sub getID {
    my($username) = @_;

    ## if already in the DB
    return $username_id{$username} if $username_id{$username};

    ## else do an API hit for it
    checkAuth();
    
    my $r = undef;

    while (!$r) {
        eval {
            $r = $nt->lookup_users({ screen_name => $username });            
        };
        if ($@) {
            warn $@, "\n";
            if ($@ =~ /Rate limit/) {           
                sleep $nt->until_rate(1.0);
            } elsif($@ =~/Not Found/) {
                $invalid_users{$username} = 1;
                return 0;
            }
        }

        sleep(1);
    }

    ## get the queried user
    my($user)    = (@{ $r })[0];
    my($user_id) = $user->{id};
    
    if ($user_id) {
        my($sql) = "INSERT INTO username_id (username, user_id) VALUES (?, ?)";
        my($sth) = $dbh->prepare($sql);
        
        $username_id{$username} = $user_id if $sth->execute($username, $user_id);                
        return $user_id;    
    }
}

sub getCandidate {
    my($username, $user_id) = @_;

    checkAuth();
    $user_id = getID($username) unless $user_id;

    ## return false if no user id can be found
    return 0 unless $user_id;

    my($r) = undef;
    while (!$r) {
        eval {
            $r = $nt->user_timeline({ user_id => $user_id });
        };
        if ($@) {
            warn $@;
            if ($@ =~ /Rate limit/) {           
                sleep $nt->until_rate(1.0);
            } else {
                $invalid_users{$username} = 1;
                return 0;
            }
        }
    }

    my(@statuses) = @{ $r };    
        
    unless ($stored_cands{$user_id}) { 
        ## we have not seen this user before
        unless ($stored_users{$user_id}) {
            addUser($user_id, 1);
        } else {
            ## we've seen this user and need to mark it as a candidate
            updateUser($user_id, 1);
        }
        
        $stored_cands{$user_id}++;
    }
}

sub getRelation {
    my($user_id, $type) = @_;
    
    checkAuth();

    my $cursor = -1;
    
    while ($cursor != 0) {    
        my $res = undef;
        
        eval {
            if ($type eq 'followers') {
                $res = $nt->followers_ids({ id => $user_id, cursor => $cursor });
            } elsif ($type eq 'friends') {
                $res = $nt->friends_ids({ id => $user_id, cursor => $cursor });
            }
        };
        unless ($@) {
            foreach my $id (@{ $res->{ids} }) {
                addUser($id, 0) unless $stored_users{$id};
                                
                if ($type eq 'followers') {
                    addRelation($id, $user_id) unless $stored_relations{ $id . '-' . $user_id };
                } elsif ($type eq 'friends') {
                    addRelation($user_id, $id) unless $stored_relations{ $user_id . '-' . $id };
                }
            }
            
            $cursor = $res->{next_cursor};
        } else {
            warn $@;
            if ($@ =~ /Rate limit/) {           
                sleep $nt->until_rate(1.0);
            }
        }

        sleep(1);
    }
}

sub restore_tokens {
    my($sql) = 'SELECT option_key, option_value FROM twit_options WHERE option_key IN (?,?)';
    my($sth) = $dbh->prepare($sql);
    $sth->execute('access_token', 'access_token_secret');

    while(my($key, $val) = $sth->fetchrow_array()) {
        if ($key eq 'access_token') {
            $access_token = $val;
        } elsif ($key eq 'access_token_secret') {
            $access_token_secret = $val;
        }
    }

    if ($access_token) {
        $nt->access_token($access_token);
        $nt->access_token_secret($access_token_secret);
    }
}

sub save_tokens {
    my($at, $ats) = @_;

    ## in the db
    if ($access_token) {
        my($sql) = 'UPDATE twit_options SET option_value = ? WHERE option_key = ?';
        my($sth) = $dbh->prepare($sql);
        $sth->execute($at, 'access_token');

        $sth = $dbh->prepare($sql);
        $sth->execute($ats, 'access_token_secret');
    } else {
        my($sql) = 'INSERT INTO twit_options (option_key, option_value) VALUES (?,?),(?,?)';
        my($sth) = $dbh->prepare($sql);
        $sth->execute('access_token', $at,
                      'access_token_secret', $ats);
    }
}

sub main {
#    For the initial run

#    my($sql) = "SELECT username FROM candidate_queue";
#    my($sth) = $dbh->prepare($sql);
#    $sth->execute();

    my(@users) = ();

    ## get the username to ID map
    my($sql) = "SELECT username, user_id FROM username_id";
    my($sth) = $dbh->prepare($sql);
    $sth->execute();

    while(my($username, $user_id) = $sth->fetchrow_array()) {
        $username_id{$username} = $user_id;
    }

    ## get the relations
    $sql = "SELECT user1, user2 FROM relation";
    $sth = $dbh->prepare($sql);
    $sth->execute();

    while (my($user1, $user2) = $sth->fetchrow_array()) {
        $stored_relations{ $user1 . '-' . $user2 } = 1;
    }

    ## the candidates will be the ones worked on

    ## get all the users
    $sql = "SELECT uid.username, f.user_id, f.is_candidate FROM follow f LEFT JOIN username_id uid ON (f.user_id = uid.user_id)";
    $sth = $dbh->prepare($sql);
    $sth->execute();

    while(my($username, $user_id, $is_candidate) = $sth->fetchrow_array()) {
        if ($is_candidate) {
            $stored_cands{$user_id} = 1;
            push @users, $username;
        }

        $stored_users{$user_id} = 1;
    }

    ## get the tokens from the API
    restore_tokens();

    foreach my $username (@users) {
        print "User: $username", "\n";
        my $status = getCandidate($username, $username_id{$username});
        
        ## skip if bad status
        next() unless $status;

        getRelation($username_id{$username}, 'followers');
        getRelation($username_id{$username}, 'friends');        

        sleep(1);
    }

    print 'Added candidates: ', scalar(keys %stored_cands), "\n";

    print 'Invalid users: ', scalar(keys %invalid_users), "\n";
    print '(', (join ',', keys %invalid_users), ')', "\n";

    print 'Total candidates in queue: ', scalar(@users), "\n";
}

main();

__END__
