#!/usr/bin/perl

use strict;
use warnings;
use diagnostics;
use Rcon::KKrcon;

local $| = 1;

&load_config_file('nanny.cfg');

my $address;
my $port;
my $password;
my $command = join("", @ARGV);
my $rcon = new KKrcon(
    Host     => $address,
    Port     => $port,
    Password => $password,
    Type     => 'old'
);
my $result = 0;
my $interactive = 1 unless ($command);

print "Type 'exit' to quit.\n\n";

while (1) {
    print "KKrcon> ";
    $command = <STDIN>;
    if (!defined($command)) {
        print "\n";
        exit(0);
    }
    chomp($command);
    if ($command =~ /^\s*$/) { next; }
    if ($command eq "q" or $command eq "quit" or $command eq "exit") {
        exit(0);
    }
    $result = &execute($command);
    exit($result) unless ($interactive);
}

sub load_config_file {
    my $config_file = shift;
    if (!defined($config_file)) {
        &die_nice("load_config_file called without an argument\n");
    }
    if (!-e $config_file) {
        &die_nice("load_config_file config file does not exist: $config_file\n");
    }
    open(CONFIG, $config_file)
      or &die_nice("$config_file file exists, but i couldnt open it.\n");
    my $line;
    my $config_name;
    my $config_val;
    print "\nParsing config file: $config_file...\n\n";

    while (defined($line = <CONFIG>)) {
        $line =~ s/\s+$//;
        if ($line =~ /^\s*(\w+)\s*=\s*(.*)/) {
            ($config_name, $config_val) = ($1, $2);
            if ($config_name eq 'ip_address') {
                $address = $config_val;
                print "Server IP address: $address\n";
            }
            elsif ($config_name eq 'port') {
                $port = $config_val;
                print "Server port number: $port\n";
            }
            elsif ($config_name eq 'rcon_pass') {
                $password = $config_val;
                print "RCON password: " . '*' x length($password) . "\n";
            }
        }
    }
    print "\n";
}

sub execute {
    my ($command) = @_;
    my $error;
    $command =~ s/\/\/+/\//g;
    print $rcon->execute($command) . "\n";

    if ($error = $rcon->error) {
        if ($error eq 'Rcon timeout') {
            print "rebuilding rcon object\n";
            $rcon = new KKrcon(
                Host     => $address,
                Port     => $port,
                Password => $password,
                Type     => 'old'
            );
        }
        else { print "WARNING: rcon error: $error\n"; }
        return 1;
    }
    else { return 0; }
}

sub die_nice {
    my $message = shift;
    if ((!defined($message)) or ($message !~ /./)) {
        $message = 'default die_nice message.\n\n';
    }
    print "\nCritical Error: $message\n\n";
    exit 1;
}
