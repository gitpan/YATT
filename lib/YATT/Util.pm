# -*- mode: perl; coding: utf-8 -*-
package YATT::Util;
use base qw(Exporter);
use strict;
use warnings FATAL => qw(all);

use Carp;

BEGIN {
  our @EXPORT_OK
    = qw(&optional
	 &try_can

	 &require_and

	 &default
	 &coalesce
	 &numeric

	 &lsearch
	 &escape
	 &decode_args
	 &named_attr
	 &resume

	 &line_info
	 &needs_line_info

       );
  our @EXPORT = @EXPORT_OK;
}

sub optional {
  my ($hash, $member, $key) = @_;
  defined (my $value = $hash->{$member}) or return;
  ($key, $value);
}

sub try_can {
  my ($obj, $method) = splice @_, 0, 2;
  my $sub = $obj->can($method) or return;
  $sub->($obj, @_);
}

sub require_and {
  my ($class) = shift;
  my $method = shift;
  unless ($class->can($method)) {
    eval "require $class";
    die $@ if $@;
  }
  $class->$method(@_);
}

sub coalesce {
  foreach my $item (@_) {
    return $item if defined $item;
  }
}
*default = *coalesce; *default = *coalesce;
sub numeric {
  default(@_, 0);
}

sub lsearch (&$;$) {
  my ($cmp, $list, $i) = @_;
  $i = 0 unless defined $i;
  foreach (@{$list}[$i .. $#$list]) {
    return $i if $cmp->();
  } continue {
    $i++;
  }
  return
}

my %escape = (qw(< &lt;
		 > &gt;
		 " &quot;
		 & &amp;)
	      , "\'", "&#39;");

our $ESCAPE_UNDEF = '';

sub escape {
  return if wantarray && !@_;
  my @result;
  foreach my $str (@_) {
    push @result, do {
      unless (defined $str) {
	$ESCAPE_UNDEF;
      } elsif (ref $str eq 'SCALAR') {
	# PASS Thru. (Already escaped)
	$$str;
      } else {
	$str =~ s{([<>&\"\'])}{$escape{$1}}g;
	$str;
      }
    };
  }
  wantarray ? @result : $result[0];
}

sub _handle_arg_desc {
  my ($desc) = shift;
  unless (defined $desc->[2]) {
    # '?' case.
    defined $_[0] && $_[0] ne '' ? $_[0] : $desc->[1];
  } elsif (ref $desc->[2]) {
    # extension.
    $desc->[2]->($desc->[1], $_[0]);
  } elsif ($desc->[2] eq '/') {
    defined $_[0] ? $_[0] : $desc->[1];
  } elsif ($desc->[2] eq '|') {
    $_[0] ? $_[0] : $desc->[1];
  } else {
    confess "Invalid arg spec $desc->[2] for $desc->[0]";
  }
}

sub decode_args {
  my ($args) = shift;
  unless (defined $args) {
    map {
      ref $_[$_] eq 'ARRAY' ? $_[$_]->[1] : undef;
    } 0 .. $#_;
  } elsif (ref $args eq 'ARRAY') {
    map {
      unless (ref $_[$_]) {
	$args->[$_];
      } else {
	_handle_arg_desc($_[$_], $args->[$_]);
      }
    } 0 .. $#_;
  } else {
    my @args;
    foreach my $desc (@_) {
      push @args, do {
	unless (ref $desc) {
	  delete $args->{$desc};
	} else {
	  _handle_arg_desc($desc, delete $args->{$desc->[0]});
	}
      };
    }
    if (%$args) {
      my ($pkg, $file, $line) = caller(0);
      die "Invalid args at $file line $line: "
	. join(", ", sort keys %$args) . "\n";
    }
    @args;
  }
}

sub named_attr {
  my ($attname, $value, $spc) = @_;
  return '' unless defined $value && $value ne '';
  sprintf('%s%s="%s"', defined $spc ? $spc : ' '
	  , $attname, YATT::escape($value));
}

sub resume {
  my ($CGI, $name, $value, $type) = @_;
  unless (defined $type) {
    ""
  } elsif ($type =~ /^(?:radio|checkbox)$/i) {
    my $cache = $CGI->{'.RESUME_CACHE'}->{$name} ||= do {
      my %cache;
      $cache{$_} = 1 for $CGI->param($name);
      \%cache;
    };
    $cache->{$value} ? "checked" : "";
  } elsif ($type =~ /^(?:|text|password)$/i) {
    named_attr(value => scalar $CGI->param($name), ' ');
  } else {
    # textarea と select option の selected. (multi もあるでよ)
  }
}

BEGIN {
  my $db = $main::{"DB::"};
  # check if DB::sub exists.
  if (defined $db and defined ${*{$db}{HASH}}{sub}
      and not $ENV{DEBUG_DETAIL}) {
    *needs_line_info = sub () { 0 };
    *line_info = sub {""};
    require Scalar::Util;
    *put_debuginfo = sub {
      my ($pack, $fn) = splice @_, 0, 2;
      @{$main::{"_<$fn"}} = (undef, map {
	Scalar::Util::dualvar(1, $_);
      } split /(?<=\n)/, $_[0]);
    };
  } else {
    *needs_line_info = sub () { 1 };
    *line_info = sub {
      my ($offset) = @_;
      my ($pack, $file, $line) = caller;
      sprintf(qq|#line %d "%s"\n|, $line + $offset, $file)
    };
    *put_debuginfo = sub () {};
  }
}
1;
