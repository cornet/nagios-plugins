#!/usr/bin/env perl

###############################################################################
##
## check_jk_status:
##
## Check the status for mod_jk's loadbalancers via XML download from status 
## URL.
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
##
## $Id: check_jk_status.pl,v 1.1 2010/07/23 10:15:03 nathan Exp $
##
###############################################################################

use strict;
use warnings;
use XML::Simple;
use Data::Dumper;
use Getopt::Long;

####################################################
## Global vars
####################################################

## Initialize vars
my $server_ip = '';
my $balancer  = '';
my $uri       = '';

## Get user-supplied options
GetOptions('host=s' => \$server_ip, 'balancer=s' => \$balancer, 'uri=s' => \$uri);

####################################################
## Main APP
####################################################

if ( ($server_ip eq '') || ($balancer eq '') || ($uri eq ''))
{
  print "\nError: Parameter missing\n";
  &Usage();
  exit(1);
}

## Fetch the status
my $xml = FetchStatus($server_ip, $uri);

## Parse the XML and return the results
ParseXML($xml);

###################################################
## Subs / Functions
####################################################

## Print Usage if not all parameters are supplied
sub Usage() 
{
  print "\nUsage: check_jk_status [PARAMETERS]

Parameters:
  --host=[HOSTNAME]        : Name or IP address of JK management interface
  --uri=[URI]              : URI to status page. E.g. /jkmanager/
  --balancer=[JK BALANCER] : Name of the JK balancer\n\n";
}

## Fetch the XML from management address
sub FetchStatus
{
    ### Get the ip for connect
    my $ip = shift;

    ## Get URI
    my $uri = shift;
    
    ### Generate unique output file
    my $unique = `uuidgen`;
    chomp ($unique);
    $unique .= ".xml";
    
    ### Construct URL
    my $url = "http://$ip/$uri/?mime=xml";
    
    ### Fetch XML
    open(FETCH, "wget -q -O /tmp/$unique $url >/dev/null 2>&1 |") || PrintExit("Failed to run wget: $!");
    close(FETCH);

    PrintExit ("Unable to fetch status XML!") unless ( $?>>8 == 0 );
    
    ## Sleep a second
    sleep(1);

    ## Return the fetched XML
    return $unique;
}

## Parse the XML and return the results
sub ParseXML
{
    ### Get XML to parse
    my $xml = shift;
    
    ### Hash for node status
    my @good_members = ();
    my @bad_members = ();

    ### Convert XML to hash
    my $status = XMLin("/tmp/$xml", forcearray => ['jk:member']);
    
    ### Exit if specified balancer wasn't found
    PrintExit ("Supplied balancer wasn't found!") unless defined ( %{$status->{'jk:balancers'}->{'jk:balancer'}->{$balancer}} );
    
    ### Get number of members
    my $member_count = $status->{'jk:balancers'}->{'jk:balancer'}->{$balancer}->{'member_count'};
    
    ### Check all members
    foreach my $member ( sort keys %{$status->{'jk:balancers'}->{'jk:balancer'}->{$balancer}->{'jk:member'}} )
    {
        ### Check status for every node activation
        my $activation = $status->{'jk:balancers'}->{'jk:balancer'}->{$balancer}->{'jk:member'}->{$member}->{'activation'};
        my $state = $status->{'jk:balancers'}->{'jk:balancer'}->{$balancer}->{'jk:member'}->{$member}->{'state'};
        
        if ( $activation ne 'ACT' )
        {
            push (@bad_members, $member);
        }
        elsif ( $activation eq 'ACT' )
        {
            if ( ($state ne 'OK') && ($state ne 'OK/IDLE') )
            {
                #print "STATE: $state\n";
                push (@bad_members, $member);
            }
            else
            {
                push (@good_members, $member);
            }
        }
    }
    
    ### Calaculate possible differnece
    my $good_boys = $member_count - scalar(@bad_members);
    
    if ( $member_count == $good_boys )
    {
        print "All members are fine";
	unlink("/tmp/$xml") || PrintExit("Could not delete: $!");
        exit 0;

    }
    else
    {
        print scalar(@bad_members), " of $member_count members are down";
	unlink("/tmp/$xml") || PrintExit("Could not delete: $!");
        exit 2;
    }
}

sub PrintExit
{
    my $msg = shift;
    print $msg;
    exit 1;
}
    
