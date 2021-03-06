# Copyright (C) 2011–2015  Alex Schroeder <alex@gnu.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

use strict;
# use warnings;
use v5.10;

AddModuleDescription('google-plus-one.pl', 'Google Plus One Module');

our ($q, $RCName, @MyFooters, @MyAdminCode, %Action, @MyInitVariables, $CommentsPrefix);

my $data_uri = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEwAAAAYCAMAAABnVuv4AAAAhFBMVEUAAAD////MzMz5+fkWau+zs7Pg4OD39/fh4eHu7u7z8/Pk5OTm5ubX19fx8fHj4+N+fn5jY2Ojo6N/f3/r7Ov29vbq6ero6Oj19fUVau0XafC3zO3q6ulKie2dve89ge1yoexkmeyNsepZk+/T3u4weu4jcu7E1Ox9p+rExMTX4vLi6PBsAh6oAAAAAXRSTlMAQObYZgAAAWtJREFUOMvFldluwjAQRU24LgHTpAsEgglL2Nv//7/OeGLLqlTXD5V6HM/c2NJRMJGilClSGCW8DbwEXgPvA+QqRylKI66kLNiKUZri72X6OQOdKxtn8E+yCTMOjQdBhbvEbNkkA5EBoJKULdc0ltHksv447ZaM7JJMNO1PstLZ9Gw2W9PgSxJXe4V1QZZIxiIGI4AbWs5hso1lFY0BwLXzEcBnWK8qJ9uIDKxlMbjyKnex6SoCcO2CKy7xupxZG57GKSBBbsSmp56btYC1t+l5v9vhNI0QmZyZVC+DPKa4IlkHR8f5gD4hQyzb0AhntvAcuo5U3YHzvrWLCJZFmlZ+pp/Rv9k022a75do0ABWKHCTJ9e0923Bmn6ij92xOrAaA1YpvLPZzCrJO+yxLE2Rm7rnfpfc4UjV+x2TLzEBtAvURvYnIl9UDJU8qcsmSL9myMoNs2VMGWtVZHxT9+N310ErVRYpaCToD9QXtvTL0OWiBLQAAAABJRU5ErkJggg==';

# Make sure journal pages set a global variable which we then use to
# hide the +1 button.

*OldGooglePlusPrintJournal = \&PrintJournal;
*PrintJournal = \&NewGooglePlusPrintJournal;

my $GooglePlusThisPagePrintedJournal;

push(@MyInitVariables, sub {
  $GooglePlusThisPagePrintedJournal = 0;
     });

sub NewGooglePlusPrintJournal {
  $GooglePlusThisPagePrintedJournal = 1;
  return OldGooglePlusPrintJournal(@_);
}

# Use a two step Google +1 button to protect your privacy: show this
# at the bottom of every page but not on comment pages, Recent
# changes, and pages that printed a journal.

unshift(@MyFooters, \&GooglePlusPrintFooter);

sub GooglePlusPrintFooter {
  my ($id, $rev, $comment) = @_;
  if (not $GooglePlusThisPagePrintedJournal
      and (GetParam('action', 'browse') eq 'plusone'
	   or (GetParam('action', 'browse') eq 'browse'
	       and $id
	       and $id ne $RCName
	       and (not $CommentsPrefix or $id !~ /^$CommentsPrefix(.*)/)))) {
    return q{
<!-- start of Google+ -->
<script type="text/javascript">
function loadScript(jssource) {
   // add javascript
   var jsnode = document.createElement('script');
   jsnode.setAttribute('type','text/javascript');
   jsnode.setAttribute('src',jssource);
   document.getElementsByTagName('head')[0].appendChild(jsnode);
   // add button
   var butn = document.createElement('div');
   butn.setAttribute('class', 'g-plusone');
   butn.setAttribute('id', 'my_plusone');
   var link = document.getElementById('plus1');
   link.parentNode.insertBefore(butn, link);
   // hide the link
   link.innerHTML = "";
   // when looking at action=plusone
   var ul = document.getElementById('plus1s');
   var children = ul.children;
   for (var i = 0; i < children.length; i++) {
     var li = children[i];
     butn = document.createElement('g:plusone');
     butn.setAttribute('href', li.firstElementChild.getAttribute('href'));
     butn.setAttribute('id', 'my_plusone' + i);
     li.appendChild(butn);
   }
 }
</script>
<p id="plus1">
  <a href="javascript:loadScript('https://apis.google.com/js/plusone.js')">
    <img src="/pics/plusone-h24.png" alt="Show Google +1" />
  </a>
</p>
<!-- end of Google+ -->
};
  }
}

# Google +1 list

push(@MyAdminCode, sub {
       my ($id, $menuref, $restref) = @_;
       push(@$menuref, ScriptLink('action=plusone',
                                  T('Google +1 Buttons'),
                                  'plusone'));
     });

$Action{plusone} = \&DoPlusOne;

sub DoPlusOne {
  print GetHeader('', T('All Pages +1'), ''),
    $q->start_div({-class=>'content plusone'});
  print $q->p(T("This page lists the twenty last diary entries and their +1 buttons."));
  my @pages;
  foreach my $id (AllPagesList()) {
    push(@pages, $id) if $id =~ /^\d\d\d\d-\d\d-\d\d/;
  }
  splice(@pages, 0, $#pages - 19); # last 20 items
  print '<ul id="plus1s">';
  foreach my $id (@pages) {
    print $q->li(GetPageLink($id), ' ');
  }
  print "</ul>";
  print $q->end_div();
  PrintFooter();
}
