#!/usr/bin/perl
# 
# Twitter streaming API collector, v1
# Author: Alexander Hanna
# Email: ahanna@ssc.wisc.edu
#
# June 2010

use strict;
use warnings;

use DBI;
use HTTP::Request::Common;
use LWP::UserAgent;
################################################################################

# From Twitter API pages:
# There are four main reasons to have your connection closed:
#   Duplicate clients logins (earlier connections terminated)
#   Hosebird server restarts (code deploys)
#   Lagging connection terminated (client too slow, or insufficient bandwidth)
#   General Twitter network maintenance (Load balancer restarts, network reconfigurations, other very very rare events)

my($wait_httperr) = 10;
my($wait_tcpip)   = 0.25;

my($dbname) = '';
my($dbhost) = '';
my($dbuser) = '';
my($dbpass) = '';

my($dbh) = DBI->connect("DBI:mysql:database=$dbname;hostname=$dbhost;port=3306", 
                        $dbuser, 
                        $dbpass) or die $DBI::errstr;

my($inserted)  = 0;
my($data_chunk) = '';

sub sleep_error {
    my($response) = @_;
    my $currTime  = localtime;

    print STDERR $currTime, "\t", "[HTTP: " . $response->status_line() . "]\tWaiting for $wait_httperr seconds...\n";

    ## sleep for selected seconds then double if less than 240
    sleep($wait_httperr);
    
    $currTime = localtime;
    print STDERR "[$currTime]", "\t", "Resuming...", "\n";

    $wait_httperr *= 2 unless $wait_httperr >= 240;
}

sub res_handler {
    my($response, $ua, $h, $data) = @_;
    my($sql, $sth) = ();

    if ($response->code() == 401) {            
        print STDERR "[HTTP]\tWaiting for 1 second...\n";
        sleep(1);
    } elsif ($response->code() > 400) { 
        sleep_error($response);
    } else {
        ## reset error waits
        $wait_httperr = 10   if $wait_httperr > 10;
        $wait_tcpip   = 0.25 if $wait_tcpip > 0.25;

        ## if the stored data chunk doesn't end with a newline,
        ## there is more to it
        if ($data  !~ /^.+\n$/) {
            $data_chunk .= $data;
        } elsif ($data_chunk !~ /^.+\n$/) {  
            ## otherwise, if the data_chunk doesn't end with a newline 
            ## but the current one does, store it and reset the chunk
            $data_chunk .= $data;

#            print $data_chunk;
            ## put the data in a database as text, to be sorted out later

            $sql = "INSERT INTO firehose_queue (json) VALUES (?)";
            $sth = $dbh->prepare($sql);
            $inserted++ if $sth->execute( $data_chunk );
            $data_chunk = '';
        }
    }

    return 1;
}

sub setupForm {

    ## Where we query for who we want to follow
    my($sql) = "SELECT user_id FROM follow_sample";
    my($sth) = $dbh->prepare($sql);
    $sth->execute( $offset, $limit );

    my(@users) = ();
    while(my($user) = $sth->fetchrow_array()) {
        push @users, $user;
    }

    print scalar(@users), "\n";

    my(%form) = (
        'follow' => join ',', @users
        );

    return \%form;
}

## TK: Need to convert this to secure

sub run_thread {
    my($stream_url) = 'https://stream.twitter.com/1/statuses/filter.json';

    my($username) = $ARGV[0];
    my($password) = '';

    my(%form) = %{ setupForm( ) };
    
    my $ua = LWP::UserAgent->new();
    $ua->add_handler( 'response_data' => \&res_handler );

    ## HTTP Basic Auth
    $ua->credentials("stream.twitter.com:80", "Firehose", $username, $password );
    
    ## the response handler does all the handling in the request
    ## TCP/IP errors will live here    
    while(my $res = $ua->request(POST $stream_url, \%form)) {
        ## weird auth error, just continue
        if ($res->code() == 401) {            
            print STDERR "[HTTP]\tWaiting for $wait_httperr seconds...\n";
            sleep(1);
        } elsif ($res->code() == 413) { ## entity too large
            sleep_error($res);  ## try again 
        } elsif ($res->code() > 400) {
            sleep_error($res);
        } else {
            my $currTime = localtime;
            print STDERR "[$currTime]", "\t", "[TCP/IP: " . $res->status_line() . "]", "\t", "Waiting for $wait_tcpip seconds...\n";
            
            ## if it has gotten here, it is probably a TCP/IP error
            sleep($wait_tcpip);

            $currTime = localtime;
            print STDERR "[$currTime]", "\t", "Resuming...", "\n";

            $wait_tcpip  += 0.25 unless $wait_tcpip >= 16;
            $wait_httperr = 10;
        }
    }
}


sub main {

    run_thread();
}

# Pre-launch checklist
#   Not purposefully attempting to circumvent access limits and levels?
#   Creating the minimal number of connections?
#   Avoiding duplicate logins?
#   Backing off from failures: none for first disconnect, seconds for repeated network (TCP/IP) level issues, minutes for repeated HTTP (4XX codes)?
#   Using long-lived connections?
#   Tolerant of other objects and newlines in markup stream? (Non <status> objects...)
#   Tolerant of duplicate messages?
#   Using JSON if at all possible?

main();

__END__
