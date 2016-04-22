package KKrcon;

# KKrcon Perl Module - execute commands on a remote Half-Life server using Rcon.
# http://kkrcon.sourceforge.net
#
# Synopsis:
#
# use KKrcon;
# $rcon = new KKrcon(Password=>PASSWORD, [Host=>HOST], [Port=>PORT]);
# $result  = $rcon->execute(COMMAND);
#
# Copyright (C) 2000, 2001  Rod May
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

use warnings;
use strict;
use Socket;

# Main
sub new {
	my $class_name = shift;
	my %params     = @_;
	my $self       = {};
	bless($self, $class_name);

	# Check parameters
	$params{"Host"} = "127.0.0.1" unless ($params{"Host"});
	$params{"Port"} = "28960"     unless ($params{"Port"});

	# Initialise properties
	$self->{"rcon_password"} = $params{"Password"} or die("KKrcon: a Password is required\n");
	$self->{"server_host"}   = $params{"Host"};
	$self->{"server_port"}   = int($params{"Port"}) or die("KKrcon: invalid Port \"" . $params{"Port"} . "\"\n");
	$self->{"error"}         = "";

	# Set up socket parameters
	$self->{"ipaddr"} = gethostbyname($self->{"server_host"}) or die("KKrcon: could not resolve Host \"" . $self->{"server_host"} . "\"\n");

	return $self;
}

# Execute an Rcon command and return the response
sub execute {
	my ($self, $command) = @_;
	my $msg;
	my $ans;

	# Say hack to match non-ascii characters
	if ($command =~ /^say\s(.*)/) { $command = "say " . '"' . "$1" . '"'; }

	$msg = "\xFF\xFF\xFF\xFFrcon " . $self->{"rcon_password"} . " $command";
	$ans = $self->sendrecv($msg);

	return $ans;
}

sub sendrecv {
	my ($self, $msg) = @_;
	my $host   = $self->{"server_host"};
	my $port   = $self->{"server_port"};
	my $ipaddr = $self->{"ipaddr"};

	# Open socket
	socket(RCON, PF_INET, SOCK_DGRAM, getprotobyname("udp")) or die("KKrcon: socket: $!\n");

	my $hispaddr = sockaddr_in($port, $ipaddr);
	unless (defined(send(RCON, $msg, 0, $hispaddr))) { print("KKrcon: send $ipaddr:$port : $!"); }

	my $rin;
	vec($rin, fileno(RCON), 1) = 1;
	my $ans;

	if (select($rin, undef, undef, 10.0)) {
		$hispaddr = recv(RCON, $ans, 8192, 0);
		if (defined($ans)) {
			$ans =~ s/^\xFF\xFF\xFF\xFFprint\n//;    # CoD2 response
			$ans =~ s/\s+$//;                        # trailing spaces

			if (length($ans) > 1024) {

				# my ugly hack for long responses.
				#  - smug
				my $lol;
				my @explode;
				while (select($rin, undef, undef, 0.05)) {

					# this really sucks.  We're missing a byte and I can't find it
					# BECAUSE ITS NOT THERE.
					# fuckers.  This seems to be a bug in the game.
					# Even the in-game /rcon command has the missing-byte bug.
					# Now that we know we can't fix it now we mark it as corrupt.
					# First, we mark the begining of the last line of what we've received
					# so far as being corrupt.
					@explode = split(/\n/, $ans);
					$explode[$#explode] =~ s/^ //;
					$explode[$#explode] = 'X' . $explode[$#explode];
					$ans = join("\n", @explode);

					# now we receive, strip again, and append.
					$hispaddr = recv(RCON, $lol, 8192, 0);
					if (defined($lol)) {
						$lol =~ s/^\xFF\xFF\xFF\xFFprint\n//;    # CoD2 response
						$lol =~ s/\s+$//;                        # trailing spaces
						$ans .= $lol;
					}
				}

				# End of the llama / platypus ugly hack for long responses.
			}
		}
	}

	# Close socket
	close(RCON);

	if (!defined($ans)) {
		$ans = "";
		$self->{"error"} = "Rcon timeout";
	}

	return $ans;
}

sub error {
	my ($self) = @_;
	return $self->{"error"};
}

# End
1;
