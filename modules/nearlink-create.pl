# Copyright (C) 2006  Alex Schroeder <alex@emacswiki.org>
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

AddModuleDescription('nearlink-create.pl', 'Comments on Near Links');
our (%InterSite, $FreeLinkPattern);

*OldNearCreateScriptLink = \&ScriptLink;
*ScriptLink = \&NewNearCreateScriptLink;

sub NewNearCreateScriptLink {
  my ($action, $text, $class, $name, $title, $accesskey, $nofollow) = @_;
  my $html = OldNearCreateScriptLink(@_);
  if ($class eq 'near' and $text =~ /^$FreeLinkPattern$/) {
    # Hack alert: For near links, $action will contain an URL, not the
    # id. The NearSite is stored in $name.
    my $id = UrlDecode($action);
    if ($id =~ s/$InterSite{$title}// and $id =~ /^$FreeLinkPattern$/) {
      $action = 'action=edit;id=' . UrlEncode(FreeToNormal($id));
      $html .= ScriptLink($action, T(' (create locally)'), 'edit create', undef,
			  T('Click to edit this page'), $accesskey);
    }
  }
  return $html;
}
