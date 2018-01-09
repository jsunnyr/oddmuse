#!/usr/bin/env perl
# Copyright (C) 2017–2018  Alex Schroeder <alex@gnu.org>

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

package OddMuse;
use strict;
use 5.10.0;
use base qw(Net::Server::Fork); # any personality will do
use MIME::Base64;

our($RunCGI, $DataDir, %IndexHash, @IndexList, $IndexFile, $TagFile, $q,
    %Page, $OpenPageName, $MaxPost, $ShowEdits, %Locks, $CommentsPattern,
    $CommentsPrefix, $EditAllowed, $NoEditFile);

OddMuse->run;

sub options {
  my $self     = shift;
  my $prop     = $self->{'server'};
  my $template = shift;

  # setup options in the parent classes
  $self->SUPER::options($template);

  # add a single value option
  $prop->{wiki} ||= undef;
  $template->{wiki} = \$prop->{wiki};

  $prop->{wiki_dir} ||= undef;
  $template->{wiki_dir} = \$prop->{wiki_dir};

  $prop->{wiki_pages} ||= [];
  $template->{wiki_pages} = $prop->{wiki_pages};
}

sub post_configure_hook {
  my $self = shift;
  $self->write_help if $ARGV[0] eq '--help';

  $DataDir = $self->{server}->{wiki_dir} || $ENV{WikiDataDir} || '/tmp/oddmuse';
  
  $self->log(3, "PID $$");
  $self->log(3, "Host " . ("@{$self->{server}->{host}}" || "*"));
  $self->log(3, "Port @{$self->{server}->{port}}");
  $self->log(3, "Wiki data dir is $DataDir\n");

  $RunCGI = 0;
  my $wiki = $self->{server}->{wiki} || "./wiki.pl";
  $self->log(1, "Running $wiki\n");
  unless (my $return = do $wiki) {
    $self->log(1, "couldn't parse wiki library $wiki: $@") if $@;
    $self->log(1, "couldn't do wiki library $wiki: $!") unless defined $return;
    $self->log(1, "couldn't run wiki library $wiki") unless $return;
  }

  # make sure search is sorted newest first because NewTagFiltered resorts
  *OldGopherFiltered = \&Filtered;
  *Filtered = \&NewGopherFiltered;
}

my $usage = << 'EOT';
This server serves a wiki as a gopher site.

It implements Net::Server and thus all the options available to
Net::Server are also available here. Additional options are available:

wiki       - this is the path to the Oddmuse script
wiki_dir   - this is the path to the Oddmuse data directory
wiki_pages - this is a page to show on the entry menu

For many of the options, more information can be had in the Net::Server
documentation. This is important if you want to daemonize the server. You'll
need to use --pid_file so that you can stop it using a script, --setsid to
daemonize it, --log_file to write keep logs, and you'll net to set the user or
group using --user or --group such that the server has write access to the data
directory.

For testing purposes, you can start with the following:

--port=7070
    The port to listen to, defaults to a random port.
--log_level=4
    The log level to use, defaults to 2.
--wiki_dir=/var/oddmuse
    The wiki directory, defaults to the value of the "WikiDataDir" environment
    variable or "/tmp/oddmuse".
--wiki_lib=/home/alex/src/oddmuse/wiki.pl
    The Oddmuse main script, defaults to "./wiki.pl".
--wiki_pages=SiteMap
    This adds a page to the main index. Can be used multiple times.
--help
    Prints this message.

Example invocation:

/home/alex/src/oddmuse/stuff/gopher-server.pl \
    --port=7070 \
    --wiki=/home/alex/src/oddmuse/wiki.pl \
    --pid_file=/tmp/oddmuse/gopher.pid \
    --wiki_dir=/tmp/oddmuse \
    --wiki_pages=Homepage \
    --wiki_pages=Gopher

Run the script and test it:

echo | nc localhost 7070
lynx gopher://localhost:7070

EOT

run();

sub NewGopherFiltered {
  my @pages = OldGopherFiltered(@_);
  @pages = sort newest_first @pages;
  return @pages;
}

sub print_text {
  my $self = shift;
  my $text = shift;
  utf8::encode($text);
  print($text); # bytes
}

sub print_menu {
  my $self = shift;
  my $selector = shift;
  my $display = shift;
  $self->print_text(join("\t", $selector, $display, $self->{server}->{sockaddr}, $self->{server}->{sockport}) . "\r\n");
}

sub print_info {
  my $self = shift;
  my $info = shift;
  $self->print_menu("i$info", "");
}

sub print_error {
  my $self = shift;
  my $error = shift;
  $self->print_menu("3$error", "");
}

sub serve_main_menu {
  my $self = shift;
  $self->log(3, "Serving main menu");
  $self->print_info("Welcome to the Gopher version of this wiki.");
  $self->print_info("Here are some interesting starting points:");

  for my $id (@{$self->{server}->{wiki_pages}}) {
    last unless $id;
    $self->print_menu("1" . NormalToFree($id), "$id/menu");
  }

  $self->print_menu("1" . "Recent Changes", "do/rc");
  $self->print_menu("7" . "Find matching page titles", "do/match");
  $self->print_menu("7" . "Full text search", "do/search");
  $self->print_menu("1" . "Index of all pages", "do/index");

  if ($TagFile) {
    $self->print_menu("1" . "Index of all tags", "do/tags");
  }

  if ($EditAllowed and not IsFile($NoEditFile)) {
    $self->print_menu("w" . "New page", "do/new");
  }

  my @pages = sort { $b cmp $a } grep(/^\d\d\d\d-\d\d-\d\d/, @IndexList);
  for my $id (@pages) {
    last unless $id;
    $self->print_menu("1" . NormalToFree($id), "$id/menu");
  }
}

sub serve_index {
  my $self = shift;
  $self->log(3, "Serving index of all pages");
  for my $id (sort newest_first @IndexList) {
    $self->print_menu("1" . NormalToFree($id), "$id/menu");
  }
}

sub serve_match {
  my $self = shift;
  my $match = shift;
  $self->log(3, "Serving pages matching $match");
  $self->print_info("Use a regular expression to match page titles.");
  $self->print_info("Spaces in page titles are underlines, '_'.");
  for my $id (sort newest_first grep(/$match/i, @IndexList)) {
    $self->print_menu( "1" . NormalToFree($id), "$id/menu");
  }
}

sub serve_search {
  my $self = shift;
  my $str = shift;
  $self->log(3, "Serving search result for $str");
  $self->print_info("Use regular expressions separated by spaces.");
  SearchTitleAndBody($str, sub {
    my $id = shift;
    $self->print_menu("1" . NormalToFree($id), "$id/menu");
  });
}

sub serve_tags {
  my $self = shift;
  $self->log(3, "Serving tag cloud");
  # open the DB file
  my %h = TagReadHash();
  my %count = ();
  foreach my $tag (grep !/^_/, keys %h) {
    $count{$tag} = @{$h{$tag}};
  }
  foreach my $id (sort { $count{$b} <=> $count{$a} } keys %count) {
    $self->print_menu("1" . NormalToFree($id), "$id/tag");
  }
}

sub serve_rc {
  my $self = shift;
  my $showedit = $ShowEdits = shift;
  $self->log(3, "Serving recent changes"
	     . ($showedit ? " including minor changes" : ""));

  $self->print_info("Recent Changes");
  if ($showedit) {
    $self->print_menu("1" . "Skip minor edits", "do/rc");
  } else {
    $self->print_menu("1" . "Show minor edits", "do/rc/showedits");
  }

  ProcessRcLines(
    sub {
      my $date = shift;
      $self->print_info("");
      $self->print_info("$date");
      $self->print_info("");
    },
    sub {
        my($id, $ts, $author_host, $username, $summary, $minor, $revision,
	   $languages, $cluster, $last) = @_;
	$self->print_menu("1" . NormalToFree($id), "$id/menu");
	$self->print_info(CalcTime($ts)
	    . " by " . GetAuthor($author_host, $username)
	    . ($summary ? ": $summary" : "")
	    . ($minor ? " (minor)" : ""));
    });
}

sub serve_page_comment_link {
  my $self = shift;
  my $id = shift;
  my $revision = shift;
  if (not $revision and $CommentsPattern) {
    if ($id =~ /$CommentsPattern/) {
      my $original = $1;
      # sometimes we are on a comment page and cannot derive the original
      $self->print_menu("1" . "Back to the original page",
		 "$original/menu") if $original;
      $self->print_menu("w" . "Add a comment", "$id/append/text");
    } else {
      my $comments = $CommentsPrefix . $id;
      $self->print_menu("1" . "Comments on this page", "$comments/menu");
    }
  }
}

sub serve_page_history_link {
  my $self = shift;
  my $id = shift;
  my $revision = shift;
  if (not $revision) {
    $self->print_menu("1" . "Page History", "$id/history");
  }
}

sub serve_file_page_menu {
  my $self = shift;
  my $id = shift;
  my $type = shift;
  my $revision = shift;
  my $code = substr($type, 0, 6) eq 'image/' ? 'I' : '9';
  $self->log(3, "Serving file page menu for $id");
  $self->print_menu($code . NormalToFree($id)
	     . ($revision ? "/$revision" : ""), $id);
  $self->serve_page_comment_link($id, $revision);
  $self->serve_page_history_link($id, $revision);
}

sub serve_text_page_menu {
  my $self = shift;
  my $id = shift;
  my $page = shift;
  my $revision = shift;
  $self->log(3, "Serving text page menu for $id"
	     . ($revision ? "/$revision" : ""));

  $self->print_info("The text of this page:");
  $self->print_menu("0" . NormalToFree($id),
	     $id . ($revision ? "/$revision" : ""));
  $self->print_menu("h" . NormalToFree($id),
	     $id . ($revision ? "/$revision" : "") . "/html");
  $self->print_menu("w" . "Replace " . NormalToFree($id),
	     $id . "/write/text");

  $self->serve_page_comment_link($id, $revision);
  $self->serve_page_history_link($id, $revision);

  my @links; # ["page name", "display text"]

  while ($page->{text} =~ /\[\[([^\]|]*)(?:\|([^\]]*))?\]\]/g) {
    if (substr($1, 0, 4) eq 'tag:') {
      push(@links, [substr($1, 4) . "/tag", $2||substr($1, 4)]);
    } else {
      push(@links, [$1 . "/menu", $2||$1]);
    }
  }

  $self->print_info("");
  if (@links) {
    $self->print_info("Links leaving " . NormalToFree($id) . ":");
    for my $link (@links) {
      $self->print_menu("1" . NormalToFree($link->[1]),
		 FreeToNormal($link->[0]));
    }
  } else {
    $self->print_info("There are no links leaving this page.");
  }

  if ($page->{text} =~ m/<journal search tag:(\S+)>\s*/) {
    my $tag = $1;
    $self->print_info("");
    $self->serve_tag_list($tag);
  }
}

sub serve_page_history {
  my $self = shift;
  my $id = shift;
  $self->log(3, "Serving history of $id");
  OpenPage($id);

  $self->print_menu("1" . NormalToFree($id) . " (current)", "$id/menu");
  $self->print_info(CalcTime($Page{ts})
      . " by " . GetAuthor($Page{host}, $Page{username})
      . ($Page{summary} ? ": $Page{summary}" : "")
      . ($Page{minor} ? " (minor)" : ""));

  foreach my $revision (GetKeepRevisions($OpenPageName)) {
    my $keep = GetKeptRevision($revision);
    $self->print_menu("1" . NormalToFree($id) . " ($keep->{revision})",
	       "$id/$keep->{revision}/menu");
    $self->print_info(CalcTime($keep->{ts})
	. " by " . GetAuthor($keep->{host}, $keep->{username})
	. ($keep->{summary} ? ": $keep->{summary}" : "")
	. ($keep->{minor} ? " (minor)" : ""));
  }
}

sub get_page {
  my $id = shift;
  my $revision = shift;
  my $page;

  if ($revision) {
    $OpenPageName = $id;
    $page = GetKeptRevision($revision);
  } else {
    OpenPage($id);
    $page = \%Page;
  }

  return $page;
}

sub serve_page_menu {
  my $self = shift;
  my $id = shift;
  my $revision = shift;
  my $page = get_page($id, $revision);

  if (my ($type) = TextIsFile($page->{text})) {
    $self->serve_file_page_menu($id, $type, $revision);
  } else {
    $self->serve_text_page_menu($id, $page, $revision);
  }
}

sub serve_file_page {
  my $self = shift;
  my $id = shift;
  my $page = shift;
  $self->log(3, "Serving $id as file");
  my ($encoded) = $page->{text} =~ /^[^\n]*\n(.*)/s;
  $self->log(4, "$id has " . length($encoded) . " bytes of MIME encoded data");
  my $data = decode_base64($encoded);
  $self->log(4, "$id has " . length($data) . " bytes of binary data");
  binmode(STDOUT, ":raw");
  print($data);
  # do not append a dot, just close the connection
  goto EXIT_NO_DOT;
}

sub serve_text_page {
  my $self = shift;
  my $id = shift;
  my $page = shift;
  my $text = $page->{text};
  $self->log(3, "Serving $id as " . length($text) . " bytes of text");
  $text =~ s/^\./../mg;
  $self->print_text($text);
}

sub serve_page {
  my $self = shift;
  my $id = shift;
  my $revision = shift;
  my $page = get_page($id, $revision);
  if (my ($type) = TextIsFile($page->{text})) {
    $self->serve_file_page($id, $page);
  } else {
    $self->serve_text_page($id, $page);
  }
}

sub serve_page_html {
  my $self = shift;
  my $id = shift;
  my $revision = shift;
  my $page = get_page($id, $revision);

  $self->log(3, "Serving $id as HTML");
  if ($revision) {
    # no locking of the file, no updating of the cache
    $self->print_text(ToString(\&PrintWikiToHTML, $page->{text}, 1));
  } else {
    $self->print_text(ToString(\&PrintPageHtml));
  }
  # do not append a dot, just close the connection
  goto EXIT_NO_DOT;
}

sub newest_first {
  my ($A, $B) = ($a, $b);
  if ($A =~ /^\d\d\d\d-\d\d-\d\d/ and $B =~ /^\d\d\d\d-\d\d-\d\d/) {
    return $B cmp $A;
  }
  $A cmp $B;
}

sub serve_tag_list {
  my $self = shift;
  my $tag = shift;
  $self->print_info("Search result for tag $tag:");
  for my $id (sort newest_first TagFind($tag)) {
    $self->print_menu("1" . NormalToFree($id), "$id/menu");
  }
}

sub serve_tag {
  my $self = shift;
  my $tag = shift;
  $self->log(3, "Serving tag $tag");
  if ($IndexHash{$tag}) {
    $self->print_info("This page is about the tag $tag.");
    $self->print_menu("1" . NormalToFree($tag), "$tag/menu");
    $self->print_info("");
  }
  $self->serve_tag_list($tag);
}

sub serve_error {
  my $self = shift;
  my $id = shift;
  my $error = shift;
  $self->log(3, "Error ('$id'): $error");
  $self->print_error("Error ('$id'): $error");
}

sub write_help {
  my $self = shift;
  my @lines = split(/\n/, <<"EOF");
This is how your document should start:
```
username: Alex Schroeder
summary: typo fixed
```
This is the text of your document.
Just write whatever.

Note the space after the colon for metadata fields.
More metadata fields are allowed:
`minor` is 1 if this is a minor edit. The default is 0.
EOF
  for my $line (@lines) {
    $self->print_info($line);
  }
}

sub write_page_ok {
  my $self = shift;
  my $id = shift;
  $self->print_info("Page was saved.");
  $self->print_menu("1" . NormalToFree($id), "$id/menu");
}

sub write_page_error {
  my $self = shift;
  my $error = shift;
  $self->log(4, "Not saved: $error");
  $self->print_error("Page was not saved: $error");
  map { ReleaseLockDir($_); } keys %Locks;
  goto EXIT;
}

sub write_data {
  my $self = shift;
  my $id = shift;
  my $data = shift;
  my $param = shift||'text';
  SetParam($param, $data);
  my $error;
  eval {
    local *ReBrowsePage = sub {};
    local *ReportError = sub { $error = shift };
    DoPost($id);
  };
  if ($error) {
    $self->write_page_error($error);
  } else {
    $self->write_page_ok($id);
  }
}

sub write_file_page {
  my $self = shift;
  my $id = shift;
  my $data = shift;
  my $type = shift || 'application/octet-stream';
  $self->write_page_error("page title is missing") unless $id;
  $self->log(3, "Posting " . length($data) . " bytes of $type to page $id");
  # no metadata
  $self->write_data($id, "#FILE $type\n" . encode_base64($data));
}

sub write_text {
  my $self = shift;
  my $id = shift;
  my $data = shift;
  my $param = shift;

  utf8::decode($data);

  my ($lead, $meta, $text) = split(/^```\s*(?:meta)?\n/m, $data, 3);

  if (not $lead and $meta) {
    while ($meta =~ /^([a-z-]+): (.*)/mg) {
      if ($1 eq 'minor' and $2) {
	SetParam('recent_edit', 'on'); # legacy UseMod parameter name
      } else {
	SetParam($1, $2);
	if ($1 eq "title") {
	  $id = $2;
	}
      }
    }
    $self->log(3, ($param eq 'text' ? "Posting" : "Appending")
	       . " " . length($text) . " characters (with metadata) to page $id");
    $self->write_data($id, $text, $param);
  } else {
    # no meta data
    $self->log(3, ($param eq 'text' ? "Posting" : "Appending")
	       . " " . length($data) . " characters to page $id") if $id;
    $self->write_data($id, $data, $param);
  }
}

sub write_text_page {
  my $self = shift;
  $self->write_text(@_, 'text');
}

sub append_text_page {
  my $self = shift;
  $self->write_text(@_, 'aftertext');
}

sub read_file {
  my $self = shift;
  my $length = shift;
  $length = $MaxPost if $length > $MaxPost;
  local $/ = \$length;
  my $buf .= <STDIN>;
  $self->log(4, "Received " . length($buf) . " bytes (max is $MaxPost)");
  return $buf;
}

sub read_text {
  my $self = shift;
  my $buf;
  while (1) {
    my $line = <STDIN>;
    if (length($line) == 0) {
      sleep(1); # wait for input
      next;
    }
    last if $line =~ /^.\r?\n/m;
    $buf .= $line;
    if (length($buf) > $MaxPost) {
      $buf = substr($buf, 0, $MaxPost);
      last;
    }
  }
  $self->log(4, "Received " . length($buf) . " bytes (max is $MaxPost)");
  utf8::decode($buf);
  $self->log(4, "Received " . length($buf) . " characters");
  return $buf;
}

sub process_request {
  my $self = shift;

  # clear cookie and all that
  $q = undef;
  Init();

  # refresh list of pages
  if (IsFile($IndexFile) and ReadIndex()) {
    # we're good
  } else {
    RefreshIndex();
  }

  eval {
    local $SIG{'ALRM'} = sub {
      $self->log(1, "Timeout!");
      die "Timed Out!\n";
    };
    alarm(10); # timeout
    my $selector = <STDIN>; # no loop
    utf8::decode($selector); # only the selector is assumed to be UTF8
    $selector =~ s/\s+$//g; # no trailing whitespace

    if (not $selector) {
      $self->serve_main_menu();
    } elsif ($selector eq "do/index") {
      $self->serve_index();
    } elsif (substr($selector, 0, 9) eq "do/match\t") {
      $self->serve_match(substr($selector, 9));
    } elsif (substr($selector, 0, 10) eq "do/search\t") {
      $self->serve_search(substr($selector, 10));
    } elsif ($selector eq "do/tags") {
      $self->serve_tags();
    } elsif ($selector eq "do/rc") {
      $self->serve_rc(0);
    } elsif ($selector eq "do/rc/showedits") {
      $self->serve_rc(1);
    } elsif ($selector eq "do/new") {
      my $data = $self->read_text();
      $self->write_text_page(undef, $data);
    } elsif ($selector =~ m!^([^/]*)/(\d+)/menu$!) {
      $self->serve_page_menu($1, $2);
    } elsif (substr($selector, -5) eq '/menu') {
      $self->serve_page_menu(substr($selector, 0, -5));
    } elsif ($selector =~ m!^([^/]*)/tag$!) {
      $self->serve_tag($1);
    } elsif ($selector =~ m!^([^/]*)(?:/(\d+))?/html!) {
      $self->serve_page_html($1, $2);
    } elsif ($selector =~ m!^([^/]*)/history$!) {
      $self->serve_page_history($1);
    } elsif ($selector =~ m!^([^/]*)/write/text$!) {
      my $data = $self->read_text();
      $self->write_text_page($1, $data);
    } elsif ($selector =~ m!^([^/]*)/append/text$!) {
      my $data = $self->read_text();
      $self->append_text_page($1, $data);
    } elsif ($selector =~ m!^([^/]*)(?:/([a-z]+/[-a-z]+))?/write/file(?:\t(\d+))?$!) {
      my $data = $self->read_file($3);
      $self->write_file_page($1, $data, $2);
    } elsif ($selector =~ m!^([^/]*)(?:/(\d+))?(?:/text)?$!) {
      $self->serve_page($1, $2);
    } else {
      $self->serve_error($selector, ValidId($selector)||'Cause unknown');
    }

  EXIT:
    # write final dot for almost everything
    $self->print_text(".\r\n");
  EXIT_NO_DOT:
    # except when sending a binary file
    $self->log(4, "Done");
  }
}
