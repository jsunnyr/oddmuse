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

AddModuleDescription('blockquote.pl', 'Comments on Text Formatting Rules');

our ($bol, @MyRules);

push(@MyRules, \&BlockQuoteRule);

sub BlockQuoteRule {
  # indented text using : with the option of spanning multiple text
  # paragraphs (but not lists etc).
  if (InElement('blockquote') && m/\G(\s*\n)+:[ \t]*/cg) {
    return CloseHtmlEnvironmentUntil('blockquote')
      . AddHtmlEnvironment('p');
  } elsif ($bol && m/\G(\s*\n)*:[ \t]*/cg) {
    return CloseHtmlEnvironments()
      . AddHtmlEnvironment('blockquote')
      . AddHtmlEnvironment('p');
  }
  return;
}
