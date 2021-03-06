# Copyright (C) 2007  Alex Schroeder <alex@emacswiki.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use v5.10;

AddModuleDescription('google-search.pl', 'Use Google For Searches');

our ($q, %Action, $ScriptName, @MyInitVariables);
our ($GoogleSearchDomain, $GoogleSearchExclusive);

$GoogleSearchDomain = undef;
$GoogleSearchExclusive = 1;

$Action{search} = \&DoGoogleSearch;

push(@MyInitVariables, \&GoogleSearchInit);

sub GoogleSearchInit {
  # If $ScriptName does not contain a hostname, this extension will
  # have no effect. Domain regexp based on RFC 2396 section 3.2.2.
  if (!$GoogleSearchDomain) {
    my $alpha = '[a-zA-Z]';
    my $alphanum = '[a-zA-Z0-9]';
    my $alphanumdash = '[-a-zA-Z0-9]';
    my $domainlabel = "$alphanum($alphanumdash*$alphanum)?";
    my $toplabel = "$alpha($alphanumdash*$alphanum)?";
    if ($ScriptName =~ m!^(https?://)?([^/]+\.)?($domainlabel\.$toplabel)\.?(:|/|\z)!) {
      $GoogleSearchDomain = $3;
    }
  }
  if ($GoogleSearchDomain
      and GetParam('search', undef)
      and not GetParam('action', undef)
      and not GetParam('old', 0)) {
    SetParam('action', 'search');
  }
  *SearchTitleAndBody = \&GoogleSearchDoNothing if $GoogleSearchExclusive;
}

# disable all other searches
sub GoogleSearchDoNothing {
  undef;
}

sub DoGoogleSearch {
  my $search = GetParam('search', undef);
  print $q->redirect({-uri=>"http://www.google.com/search?q=site%3A$GoogleSearchDomain+$search"});
}
