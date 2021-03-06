# Copyright (C) 2004, 2005, 2007  Alex Schroeder <alex@emacswiki.org>
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

AddModuleDescription('live-templates.pl', 'Live Template Extension');

our ($q, $bol, @MyRules, $FreeLinkPattern);

push(@MyRules, \&LiveTemplateRule);

sub LiveTemplateRule {
  if ($bol and /\G(&lt;&lt;$FreeLinkPattern\n)/cg) {
    Clean(CloseHtmlEnvironments());
    my $str = $1;
    my $template = FreeToNormal($2);
    /\G((.*?\n)$template(\n|\Z))/cgs or print $q->p($q->strong(T('Template without parameters')));
    $str .= $1;
    Dirty($str);
    my $oldpos = pos;
    my $old_ = $_;
    my $hash = ParseData($2);
    my $text = GetPageContent($template);
    return $q->p($q->strong(Ts('The template %s is either empty or does not exist.',
			       $template))) . AddHtmlEnvironment('p') unless $text;
    foreach my $key (keys %$hash) {
      $text =~ s/\$$key\$/$hash->{$key}/g;
    }
    print "<div class=\"template $template\">";
    ApplyRules(QuoteHtml($text), 1, 1, undef, 'p');
    $_ = $old_;
    pos = $oldpos;
    print '</div>';
    Clean(AddHtmlEnvironment('p'));
    return '';
  }
  return;
}
