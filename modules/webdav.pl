# Copyright (C) 2005–2015 Alex Schroeder <alex@emacswiki.org>
# Copyright (C) 2014–2015  Aleks-Daniel Jakimenko <alex.jakimenko@gmail.com>
# Copyright (C) 2004, Leon Brocard
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

use strict;
use v5.10;

AddModuleDescription('webdav.pl', 'WebDAV Extension');

our ($q, $Now, %Page, @KnownLocks, $DataDir);
our ($WebDavCache);

$WebDavCache = "$DataDir/webdav";
push(@KnownLocks, 'webdav');

*DavOldDoBrowseRequest = \&DoBrowseRequest;
*DoBrowseRequest = \&DavNewDoBrowseRequest;

sub DavNewDoBrowseRequest {
  my $dav = new OddMuse::DAV;
  $dav->run($q)||DavOldDoBrowseRequest();
}

*DavOldOpenPage = \&OpenPage;
*OpenPage = \&DavNewOpenPage;

sub DavNewOpenPage {
  DavOldOpenPage(@_);
  $Page{created} = $Now unless $Page{created} or $Page{revision};
}

package OddMuse::DAV;

use strict;
use warnings;
no warnings 'once'; # TODO Name "OddMuse::Var" used only once: possible typo ... ?
use HTTP::Date qw(time2str time2isoz);
use XML::LibXML;
use Digest::MD5 qw(md5_base64);

my $verbose = 0;

# These are the methods we understand -- but not all of them are truly
# implemented.
our %implemented = (
  get      => 1,
  head     => 1,
  options  => 1,
  propfind => 1,
  put      => 1,
  trace    => 1,
  lock     => 1,
  unlock   => 1,
);

sub new {
  my ($class) = @_;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub run {
  my ($self, $q) = @_;

  my $path   = $q->path_info;
  return 0 if $path !~ m|/dav|;

  my $method = $q->request_method;
  $method = lc $method;
  warn uc $method, " ", $path, "\n" if $verbose;
  if (not $implemented{$method}) {
    print $q->header( -status     => '501 Not Implemented', );
    return 1;
  }

  $self->$method($q);
  return 1;
}

sub options {
  my ($self, $q) = @_;
  print $q->header( -allow          => join(',', map { uc } keys %implemented),
		    -DAV            => 1,
		    -status         => "200 OK", );
}

sub lock {
  my ($self, $q) = @_;
  print $q->header( -status         => "412 Precondition Failed", ); # fake it
}

sub unlock {
  my ($self, $q) = @_;
  print $q->header( -status         => "204 No Content", ); # fake it
}

sub head {
  get(@_, 1);
}

sub get {
  my ($self, $q, $head) = @_;
  my $id = OddMuse::GetId();
  OddMuse::AllPagesList();
  if ($OddMuse::IndexHash{$id}) {
    OddMuse::OpenPage($id);
    if (OddMuse::FileFresh()) {
      print $q->header( -status         => '304 Not Modified', );
    } else {
      print $q->header( -cache_control  => 'max-age=10',
			-etag           => $OddMuse::Page{ts},
			-type           => "text/plain; charset=UTF-8",
			-status         => "200 OK",);
      print $OddMuse::Page{text} unless $head;
    }
  } else {
    print $q->header( -status         => "404 Not Found", );
    print OddMuse::NewText($id) unless $head;
  }
}

sub put {
  my ($self, $q) = @_;
  my $id = OddMuse::GetId();
  my $type = $ENV{'CONTENT_TYPE'};
  my $text = $q->param('PUTDATA'); # CGI.pm does that!
  # warn "text: $text\n";
  # hard coded magic based on the specs
  if (not $type) {
    if (substr($text,0,4) eq "\377\330\377\340"
	or substr($text,0,4) eq "\377\330\377\341") {
      # http://www.itworld.com/nl/unix_insider/07072005/
      $type = "image/jpeg";
    } elsif (substr($text,0,8) eq "\211\120\116\107\15\12\32\12") {
      # http://www.libpng.org/pub/png/spec/1.2/PNG-Structure.html
      $type = "image/png";
    }
  }
  # warn $type;
  if ($type and substr($type,0,5) ne 'text/') {
    require MIME::Base64;
    $text = '#FILE ' . $type .  "\n" . MIME::Base64::encode($text);
    OddMuse::SetParam('summary', OddMuse::Ts('Upload of %s file', $type));
  }
  OddMuse::SetParam('text', $text);
  local *OddMuse::ReBrowsePage;
  OddMuse::AllPagesList();
  if ($OddMuse::IndexHash{$id}) {
    *OddMuse::ReBrowsePage = \&no_content; # modified existing page
  } else {
    *OddMuse::ReBrowsePage = \&created; # created new page
  }
  OddMuse::DoPost($id); # do the real posting
}

sub no_content {
  warn "RESPONSE: 204\n\n" if $verbose;
  print CGI::header( -status         => "204 No Content", );
}

sub created {
  warn "RESPONSE: 201\n\n" if $verbose;
  print CGI::header( -status         => "201 Created", );
}

sub propfind {
  my ($self, $q) = @_;
  my $depth = $q->http('depth') || "infinity";
  warn "depth: $depth\n" if $verbose;

  # only PUT and POST are handled by CGI; for PROPFIND we need to read the body
  # ourselves
  local $/; # slurp
  my $content = <STDIN>;
  warn "PROFIND $content\n" if $verbose;

  my $parser = XML::LibXML->new;
  my $req;
  eval { $req = $parser->parse_string($content); };
  if ($@) {
    warn "RESPONSE: 400\n\n" if $verbose;
    print $q->header( -status       => "400 Bad Request", );
    print $@;
    return;
  }
  # warn "req: " . $req->toString;

  # the spec says the the reponse should not be cached...
  if ($q->http('HTTP_IF_NONE_MATCH') and GetParam('cache', $OddMuse::UseCache) >= 2
      and $q->http('HTTP_IF_NONE_MATCH') eq md5_base64($OddMuse::LastUpdate
						       . $req->toString)) {
    warn "RESPONSE: 304\n\n" if $verbose;
    print $q->header( -status       => '304 Not Modified', );
    return;
  }

  # what properties do we need?
  my $reqinfo;
  my @reqprops;
  $reqinfo = $req->find('/*/*')->shift->localname;
  if ($reqinfo eq 'prop') {
    for my $node ($req->find('/*/*/*')->get_nodelist) {
      push @reqprops, [ $node->namespaceURI, $node->localname ];
    }
  }
  # warn "reqprops: " . join(", ", map {join "", @$_} @reqprops) . "\n";

  # collection only, all pages, or single page?
  my @pages = OddMuse::AllPagesList();
  if ($q->path_info =~ '^/dav/?$') {
    # warn "collection!\n";
    if ($depth eq "0") {
      # warn "only the collection!\n";
      @pages = ('');
    } else {
      # warn "all pages!\n";
      unshift(@pages, '');
    }
  } else {
    my $id = OddMuse::GetId();
    # warn "single page, id: $id\n";
    if (not $OddMuse::IndexHash{$id}) {
      warn "RESPONSE: 404\n\n" if $verbose;
      print $q->header( -status       => "404 Not Found", );
      print OddMuse::NewText($id);
      return;
    }
    @pages = ($id);
  }
  print $q->header( -status => "207 Multi-Status",
		    -etag           => md5_base64($OddMuse::LastUpdate
						  . $req->toString)
		  );

  my $doc = XML::LibXML::Document->new('1.0', 'utf-8');
  my $multistat = $doc->createElement('D:multistatus');
  $multistat->setAttribute('xmlns:D', 'DAV:');
  $doc->setDocumentElement($multistat);

  my %data = propfind_data();
  for my $id (@pages) {
    my $title = $id;
    $title =~ s/_/ /g;
    my ($size, $mtime, $ctime) = ('', '', ''); # undefined for the wiki proper ($id eq '')
    ($size, $mtime, $ctime) = @{$data{$id}} if $id;
    my $etag = $mtime; # $mtime is $Page{ts} which is used as etag in GET
    # modified time is stringified human readable HTTP::Date style
    $mtime = time2str($mtime);
    # created time is ISO format
    # tidy up date format - isoz isn't exactly what we want, but
    # it's easy to change.
    $ctime = time2isoz($ctime);
    $ctime =~ s/ /T/;
    $ctime =~ s/Z//;
    # force empty strings if undefined
    $size ||= '';
    my $resp = $doc->createElement('D:response');
    $multistat->addChild($resp);
    my $href = $doc->createElement('D:href');
    $href->appendText($OddMuse::ScriptName . '/dav/' . OddMuse::UrlEncode($id));
    $resp->addChild($href);
    my $okprops = $doc->createElement('D:prop');
    my $nfprops = $doc->createElement('D:prop');
    my $prop;
    if ($reqinfo eq 'prop') {
      my %prefixes = ('DAV:' => 'D');
      my $i        = 0;
      for my $reqprop (@reqprops) {
        my ($ns, $name) = @$reqprop;
        if ($ns eq 'DAV:' && $name eq 'creationdate') {
          $prop = $doc->createElement('D:creationdate');
          $prop->appendText($ctime);
          $okprops->addChild($prop);
        } elsif ($ns eq 'DAV:' && $name eq 'getcontentlength') {
          $prop = $doc->createElement('D:getcontentlength');
          $prop->appendText($size);
          $okprops->addChild($prop);
        } elsif ($ns eq 'DAV:' && $name eq 'getcontenttype') {
          $prop = $doc->createElement('D:getcontenttype');
	  $prop->appendText('text/plain');
          $okprops->addChild($prop);
        } elsif ($ns eq 'DAV:' && $name eq 'getlastmodified') {
          $prop = $doc->createElement('D:getlastmodified');
          $prop->appendText($mtime);
          $okprops->addChild($prop);
        } elsif ($ns eq 'DAV:' && $name eq 'resourcetype') {
          $prop = $doc->createElement('D:resourcetype');
          if (not $id) { # change for namespaces later
            my $col = $doc->createElement('D:collection');
            $prop->addChild($col);
          }
          $okprops->addChild($prop);
        } elsif ($ns eq 'DAV:' && $name eq 'displayname') {
	  $prop = $doc->createElement('D:displayname');
	  $prop->appendText($title);
	  $okprops->addChild($prop);
        } elsif ($ns eq 'DAV:' && $name eq 'getetag') {
	  $prop = $doc->createElement('D:getetag');
	  $prop->appendText($etag);
	  $okprops->addChild($prop);
        } else {
          my $prefix = $prefixes{$ns};
          if (!defined $prefix) {
            $prefix = 'i' . $i++;
	    # mod_dav sets <response> 'xmlns' attribute - whatever
            #$nfprops->setAttribute("xmlns:$prefix", $ns);
            $resp->setAttribute("xmlns:$prefix", $ns);
            $prefixes{$ns} = $prefix;
          }
          $prop = $doc->createElement("$prefix:$name");
          $nfprops->addChild($prop);
        }
      }
    } elsif ($reqinfo eq 'propname') {
      $prop = $doc->createElement('D:creationdate');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getcontentlength');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getcontenttype');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getlastmodified');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:resourcetype');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:displayname');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getetag');
      $okprops->addChild($prop);
    } else {
      $prop = $doc->createElement('D:creationdate');
      $prop->appendText($ctime);
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getcontentlength');
      $prop->appendText($size);
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getcontenttype');
      $prop->appendText('text/plain');
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getlastmodified');
      $prop->appendText($mtime);
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:resourcetype');
      if (not $id) { # change for namespaces later
	my $col = $doc->createElement('D:collection');
	$prop->addChild($col);
      }
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:displayname');
      $prop->appendText($title);
      $okprops->addChild($prop);
      $prop = $doc->createElement('D:getetag');
      $prop->appendText($etag);
      $okprops->addChild($prop);

    }
    if ($okprops->hasChildNodes) {
      my $propstat = $doc->createElement('D:propstat');
      $propstat->addChild($okprops);
      my $stat = $doc->createElement('D:status');
      $stat->appendText('HTTP/1.1 200 OK');
      $propstat->addChild($stat);
      $resp->addChild($propstat);
    }
    if ($nfprops->hasChildNodes) {
      my $propstat = $doc->createElement('D:propstat');
      $propstat->addChild($nfprops);
      my $stat = $doc->createElement('D:status');
      $stat->appendText('HTTP/1.1 404 Not Found');
      $propstat->addChild($stat);
      $resp->addChild($propstat);
    }
  }
  warn "RESPONSE: 207\n" . $doc->toString(1) . "\n" if $verbose;
  print $doc->toString(1);
}

sub propfind_data {
  my %data = ();
  my $update = OddMuse::Modified($OddMuse::WebDavCache);
  if ($update and $OddMuse::LastUpdate == $update) {
    my $data = OddMuse::ReadFileOrDie($OddMuse::WebDavCache);
    map {
      my ($id, @attr) = split(/$OddMuse::FS/, $_);
      $data{$id} = \@attr;
    } split(/\n/, $data);
  } else {
    my @pages = OddMuse::AllPagesList();
    my $cache = '';
    foreach my $id (@pages) {
      OddMuse::OpenPage($id);
      my ($size, $mtime, $ctime);
      $size = length($OddMuse::Page{text}||0);
      $mtime = $OddMuse::Page{ts}||0;
      $ctime = $OddMuse::Page{created}||0;
      $data{$id} = [$size, $mtime, $ctime];
      $cache .= join($OddMuse::FS, $id, $size, $mtime, $ctime) . "\n";
    }
    if (OddMuse::RequestLockDir('webdav')) { # not fatal
      OddMuse::WriteStringToFile($OddMuse::WebDavCache, $cache);
      utime $OddMuse::LastUpdate, $OddMuse::LastUpdate, $OddMuse::WebDavCache; # touch index file
      OddMuse::ReleaseLockDir('webdav');
    }
  }
  return %data;
}
