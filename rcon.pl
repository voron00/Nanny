#!/usr/bin/perl

use warnings;
use strict;
use diagnostics;
use Rcon::KKrcon;

local $| = 1;
&load_config_file('nanny.cfg');
my $address;
my $port;
my $password;
my $type = 'old';
my $command = join("", @ARGV);
my $rcon = new KKrcon (Host => $address, Port => $port, Password => $password, Type => $type);
my $result = 0;
my $interactive = 1 unless ($command);

if ($interactive) { print "Type 'q' to quit.\n\n"; }

while (1)
{
        if ($interactive)
        {
	    print "kkrcon> ";

	    $command = <STDIN>;

            if (!defined($command)) {
            # catch Ctrl+D
		    print "\n";
		    exit(0);
			}

	    chomp($command);

	    if ( $command =~ /^\s*$/ ){ next; }
            if ( $command eq "q" )    { exit(0); }
            if ( $command eq "quit" ) { print "Type 'DIE' for server quit, or 'q' to quit kkrcon\n"; next; }
            if ( $command eq "DIE" )  { print "\nquit sent\n"; $command = "quit"; }
        }

        $result = &execute($command);
        exit($result) unless ($interactive);
}

sub load_config_file {
    my $config_file = shift;
    if (!defined($config_file)) { &die_nice("load_config_file called without an argument\n"); }
    if (!-e $config_file) { &die_nice("load_config_file config file does not exist: $config_file\n"); }

    open (CONFIG, $config_file) or &die_nice("$config_file file exists, but i couldnt open it.\n");

    my $line;
    my $config_name;
    my $config_val;
    my $command_name;
    my $temp;
    my $rule_name = 'undefined';
    my $response_count = 1;

    print "\nParsing config file: $config_file...\n\n";

    while (defined($line = <CONFIG>)) {
        $line =~ s/\s+$//;
        if ($line =~ /^\s*(\w+)\s*=\s*(.*)/) {
            ($config_name,$config_val) = ($1,$2);
            if ($config_name eq 'ip_address') {
                $address = $config_val;
                print "Server IP address: $address\n"; }
            elsif ($config_name eq 'port') {
                $port = $config_val;
		        print "Server port number: $port\n"; }
            elsif ($config_name eq 'rcon_pass') {
                $password = $config_val;
                print "RCON password: " . '*'x length($password) . "\n"; }
 	}
    }
    print "\n";
}

sub execute
{
    my ($command) = @_;

    print $rcon->execute($command) . "\n";

        if (my $error = $rcon->error) {
	    print "Error: $error\n";
	    return 1; }
        else { return 0; }
}

sub die_nice {
    my $message = shift;
    if ((!defined($message)) or ($message !~ /./)) {
	$message = 'default die_nice message.\n\n'; }
    print "\nCritical Error: $message\n\n";
	print "Press <ENTER> to close this program\n";
	my $who_cares = <STDIN>;
    exit 1;
}