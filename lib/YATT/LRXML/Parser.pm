package YATT::LRXML::Parser;
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Class::Configurable);
use YATT::Fields
  (qw(^tokens
      tree
      metainfo
      nsdict
      nslist
      re_splitter
      re_ns
      re_attlist
      re_entity

      re_arg_decls

      elem_kids
      cf_debug
    )
   , [cf_html_tags  => {input => 1, option => 0
			, form => 0, textarea => 0, select => 0}]
   , [cf_tokens        => qw(comment declarator pi tag entity)]
  );

use YATT::Util;
use YATT::LRXML::Node;

use YATT::LRXML ();
use YATT::LRXML::MetaInfo ();

sub MetaInfo () { 'YATT::LRXML::MetaInfo' }
sub Scanner () { 'YATT::LRXML::Scanner' }
sub Builder () { 'YATT::LRXML::Builder' }
sub Cursor () { 'YATT::LRXML::NodeCursor' }

sub after_configure {
  my MY $self = shift;
  $self->SUPER::after_configure;
  my $meta = $self->metainfo;
  $self->{nsdict} = $meta->nsdict;
  my $nslist = $self->{nslist} = $meta->cget('namespace');
  $$self{re_ns} = do {
    unless (@$nslist) {
      '';
    } else {
      my $pattern = join "|", map {ref $_ ? @$_ : $_} @$nslist;
      qq{(?:$pattern)};
    }
  };
  $$self{re_splitter} = $self->re_splitter(1, $$self{re_ns});
  $$self{re_attlist}  = $self->re_attlist(2);
  $$self{re_arg_decls} = $self->re_arg_decls(1);
  {
    my %re_cached = map {$_ => 1} grep {/^re_/} keys %$self;
    my @token_pat = $self->re_tokens(2);
    while (@token_pat) {
      my ($name, $pattern) = splice @token_pat, 0, 2;
      push @{$self->{elem_kids}}, [$name, my $pat = qr{^$pattern}];
      next unless $re_cached{"re_$name"};
      $self->{"re_$name"} = $pattern;
    }
  }
}

sub configure_namespace {
  shift->metainfo->configure(namespace => shift);
}

sub configure_metainfo {
  (my MY $self) = shift;
  if (@_ == 1) {
    $self->{metainfo} = shift;
  } elsif (not $self->{metainfo}) {
    # @_ == 0 || > 1
    $self->{metainfo} = MetaInfo->new(@_);
  } else {
    $self->{metainfo}->configure(@_);
  }
  $self->{metainfo}
}

sub metainfo {
  (my MY $self) = shift;
  $self->{metainfo} ||= $self->configure_metainfo;
}

sub parse_string {
  my MY $self = shift;
  $self->configure_metainfo(splice @_, 1);
  $self->after_configure;
  my $scan = $self->tokenize($_[0]);
  $self->organize($scan);
  # $self->{cf_document}->set_tokens($self->{tokens});
  # $self->{cf_document}->set_tree($tree);
}

#========================================

sub scanner {
  (my MY $self) = @_;
  $self->Scanner->new(array => $self->{tokens}, index => 0
		      , linenum => 1
		      , metainfo => $self->{metainfo});
}

sub tree {
  my MY $self = shift;
  my $cursor = require_and($self->Cursor
			   , new => $self->{tree}
			   , metainfo => $self->{metainfo});
  #$cursor->configure(path => $self->Cursor->Path->new($self->{tree}));
  $cursor;
}

sub organize {
  (my MY $self, my ($scan)) = @_;
  my Builder $builder
    = require_and($self->Builder
		  , new => $self->{tree} = $self->create_node('root')
		  , undef);
  while ($scan->readable) {
    my $text = $scan->read;
    $builder->add($text) if $text ne '';
    last unless $scan->readable;
    my ($toktype, @match) = $scan->expect($self->{elem_kids});
    unless (defined $toktype) {
      $builder->add($self->create_node(unknown => undef, $scan->read));
      next;
    }

    if (my $sub = $self->can("build_$toktype")) {
      # declarator も complex 扱いにした方が良いね。
      $builder = $sub->($self, $scan, $builder, \@match);
    } else {
      # easy case.
      my ($ns, $body) = @match;
      $builder->add($self->create_node($toktype => $ns, $body));
    }
  }
  $self->tree;
}

sub build_tag {
  (my MY $self, my Scanner $scan, my Builder $builder, my ($match)) = @_;
  my ($close, $html, $ns, $tagname, $attlist, $is_ee) = @$match;
  $tagname ||= $html;

  if ($close) {
    $builder->verify_close($tagname, $scan);
    # そうか、ここで attribute element からの脱出もせにゃならん。
    # switched product 方式なら、parent は共通、かな？
    return $builder->parent;
  }

  my ($is_att, $nodetype, $qflag) = do {
    if (defined $ns and $ns =~ s/^:(?=\w)//) {
      (1, attribute => YATT::LRXML::Node->quoted_by_element($is_ee));
    } elsif (defined $html) {
      $is_ee = $self->{cf_html_tags}{lc($html)};
      (0, html => $is_ee);
    } else {
      (0, element => $is_ee ? 1 : 0);
    }
  };

  my $element = $self->create_node([$nodetype, $qflag]
				   , $html
				   ? $html
				   : [$ns, split /[:\.]/, $tagname]);
  $self->parse_attlist($attlist, $element);

  unless ($is_ee) {
    # <yatt:normal>...</yatt:normal>, <:yatt:attr>...</:yatt:attr>
    $self->Builder->new($element, $builder->add($element)
			, endtag => $tagname);
  } elsif ($is_att) {
    # <:yatt:attr />...
    $builder->switch($element);
  } else {
    # <yatt:empty_elem />
    $builder->add($element);
  }
}

#========================================

sub build_declarator {
  (my MY $self, my Scanner $scan, my Builder $builder, my ($match)) = @_;
  my ($ns, $tagname, $attlist) = @$match;

  my $element = $self->create_node(declarator =>
				   [$ns, $tagname]);
  push @$element, $self->parse_arg_decls(\$attlist);

  $builder->add($element);
}

sub re_arg_decls {
  (my MY $self, my ($capture)) = @_;
  die "re_arg_decls(capture=0) is not yet implemented!" unless $capture;
  my ($SQ, $DQ) = ($self->re_sqv(2), $self->re_dqv(2));
  my $BARE = qr{([^\-\'\"\s<>/\[\]%;]+ | /(?!>))}x;
  my $ENT = qr{%([\w\:\.]+(?:[\w:\.\-=\[\]\{\}\(,\)]+)?);}x;
  qr{^ \s* -- (.*?) --
   |^ \s* $ENT
   |^  \s* (\])
   |^(?: \s+ | \s*(\[)\s* )
     (?: (\w+) \s* = \s*)?
     (?: $SQ | $DQ | $BARE)
  }xs;
}

sub parse_arg_decls {
  (my MY $self, my ($strref)) = @_;
  my @args;
  while ($$strref =~ s{$$self{re_arg_decls}}{}x) {
    print STDERR join("|", map {
      defined $_ ? $_ : "(null)"
    } $&
		      , $1 # comment
		      , $2 # ENT
		      , $3 # ]
		      , $4 # [
		      , $5 # name
		      , $6 # '..'
		      , $7 # ".."
		      , $8 # bare
		     ), "\n" if $self->{cf_debug};
    if (defined $1) { # comment
      push @args, $self->create_node(decl_comment => undef, $1);
    } elsif (defined $2) {      # ENT
      my ($ns, $body) = split /(?=:)/, $2, 2;
      ($body, $ns) = ($ns, $body) unless defined $body;
      push @args, $self->create_node(decl_entity => $ns, $body);
    } elsif (defined $3) { # ]
      last;
    } elsif (defined $4) { # [
      # XXX: hard coded.
      push @args, my $nest = $self->create_node([attribute => 3], $8);
      push @$nest, $self->parse_arg_decls($strref);
    } else {
      # $5 name
      # $6 '..'
      # $7 ".."
      # $8 bare
      push @args, $self->create_attlist($5, $6, $7, $8);
    }
  }
  print STDERR "REST<$$strref>\n" if $self->{cf_debug};
  @args;
}

#========================================

sub parse_attlist {
  my MY $self = shift;
  my $result = $_[1];		# Yes. this *is* intentional.
  # XXX: タグ内改行がここでカウントされなくなる。
  if (defined $_[0] and my @match = $_[0] =~ m{$$self{re_attlist}}g) {
    push @$result, $self->create_attlist(@match);
  }
  $result;
}

sub parse_entities {
  my MY $self = shift;
  return '' if $_[0] eq '';
  my @tokens = split $$self{re_entity}, $_[0];
  return $tokens[0] if @tokens == 1;
  my @result;
  for (my $i = 0; $i < @tokens; $i += 3) {
    push @result, $tokens[$i] if $tokens[$i] ne "";
    push @result, $self->create_node(entity => @tokens[$i+1 .. $i+2])
      if $i+2 < @tokens;
  }
  if (wantarray) {
    @result;
  } elsif (@result > 1) {
    [TEXT_TYPE, undef, @result];
  } else {
    $result[0];
  }
}

#========================================

sub tokenize {
  my MY $self = shift;
  $self->{tokens} = [split $$self{re_splitter}, $_[0]];
  if (my MetaInfo $meta = $self->{metainfo}) {
    # $meta->{tokens} = $self->{tokens};
  }
  $self->scanner;
}

sub token_patterns {
  my ($self, $token_types, $capture, $ns) = @_;
  my $wantarray = wantarray;
  my @result;
  foreach my $type (@$token_types) {
    my $meth = "re_$type";
    push @result
      , $wantarray ? $type : ()
      , $self->$meth($capture, $ns);
  }
  return @result if $wantarray;
  my $pattern = join "\n | ", @result;
  qr{$pattern}x;
}

#----------------------------------------

sub re_splitter {
  (my MY $self, my ($capture, $ns)) = @_;
  my $body = $self->re_tokens(0, $ns);
  $capture ? qr{($body)} : $body;
}

sub re_tokens {
  (my MY $self, my ($capture, $ns)) = @_;
  $self->token_patterns($self->{cf_tokens}, $capture, $ns);
}

#
# re_tag(2) returns [ /, specialtag, ns, tag, attlist, / ]
#
sub re_tag {
  (my MY $self, my ($capture, $ns)) = @_;
  my $namepat = $self->token_patterns([qw(tagname_html tagname_qualified)]
				      , $capture, $ns);
  my $attlist = $self->re_attlist;
  if (defined $capture and $capture > 1) {
    qr{<(/)? (?: $namepat) ($attlist*) \s*(/)?>}xs;
  } else {
    my $re = qr{</? $namepat $attlist* \s*/?>}xs;
    $capture ? qr{($re)} : $re;
  }
}

#----------------------------------------

sub re_name {
  my ($self, $capture) = @_;
  my $body = q{[\w\-\.]+};
  $capture ? qr{($body)} : qr{$body};
}

sub re_nsname {
  my ($self, $capture) = @_;
  my $body = q{[\w\-\.:]+};
  $capture ? qr{($body)} : qr{$body};
}

sub re_tagname_qualified {
  my ($self, $capture, $ns) = @_;
  $ns = $$self{re_ns} unless defined $ns;
  my $name = $self->re_nsname;
  if (defined $capture and $capture > 1) {
    qr{ ( :?$ns) : ($name) }xs;
  } else {
    my $re = qq{ :?$ns : $name };
    $capture ? qr{($re)}xs : qr{$re}xs;
  }
}

sub re_tagname_html {
  (my MY $self, my ($capture, $ns)) = @_;
  my $body = join "|", keys %{$self->{cf_html_tags}};
  $capture ? qr{($body)}i : qr{$body}i;
}

#----------------------------------------

sub re_attlist {
  my ($self, $capture) = @_;
  my $name =  $self->re_nsname;
  my $name_eq = defined $capture && $capture > 1
    ? qr{($name) \s* = \s*}xs : qr{$name \s* = \s*}xs;
  my $value = $self->re_attvalue($capture);
  my $re = qr{\s+ $name_eq? $value}xs;
  if (not defined $capture or $capture > 1) {
    $re;
  } else {
    qr{($re)};
  }
}

sub re_attvalue {
  my ($self, $capture) = @_;
  my ($SQ, $DQ, $NQ) =
    ($self->re_sqv($capture),
     $self->re_dqv($capture),
     $self->re_bare($capture));
  qr{$SQ | $DQ | $NQ}xs;
}

sub re_sqv {
  my ($self, $capture) = @_;
  my $body = qr{(?: [^\'\\]+ | \\.)*}x;
  $body = qr{($body)} if $capture;
  qr{\'$body\'}s;
}

sub re_dqv {
  my ($self, $capture) = @_;
  my $body = qr{(?: [^\"\\]+ | \\.)*}x;
  $body = qr{($body)} if $capture;
  qr{\"$body\"}s;
}

sub re_bare;
*re_bare = \&re_bare_torelant;

sub re_bare_strict {
  shift->re_nsname(@_);
}

sub re_bare_torelant {
  my ($self, $capture) = @_;
  my $body = qr{[^\'\"\s<>/]+ | /(?!>)}x;
  $capture ? qr{($body+)} : qr{$body+};
}

sub strip_bs {
  shift;
  $_[0] =~ s/\\(\.)/$1/g;
  $_[0];
}

#----------------------------------------

sub re_declarator {
  my ($self, $capture, $ns) = @_;
  my $namepat = $self->re_tagname_qualified($capture, $ns);
  my $arg_decls = q{[^>]+};
  if (defined $capture and $capture > 1) {
    qr{<! (?: $namepat) ($arg_decls) \s*>}xs;
  } else {
    my $re = qr{<! $namepat $arg_decls \s*>}xs;
    $capture ? qr{($re)} : $re;
  }
}

sub re_comment {
  my ($self, $capture, $ns) = @_;
  $ns = $self->re_prefix($capture, $ns, '#');
  $capture ? qr{<!--$ns\b(.*?)-->}s : qr{<!--$ns\b.*?-->}s;
}

sub re_pi {
  my ($self, $capture, $ns) = @_;
  $ns = $self->re_prefix($capture, $ns);
  my $body = $capture ? qr{(.*?)}s : qr{.*?}s;
  qr{<\?\b$ns\b$body\?>}s;
}

sub re_entity {
  shift->re_entity_pathexpr(@_);
}

# normal entity
sub re_entity_strict {
  my ($self, $capture, $ns) = @_;
  $ns = defined $ns ? qq{$ns\:} : qr{\w+:};
  my $body = $self->re_nsname;
  if (defined $capture and $capture > 1) {
    qr{&$ns($body);}xs;
  } else {
    my $re = qr{&$ns$body;}xs;
    $capture ? qr{($re)} : $re;
  }
}

# extended (subscripted) entity.
sub re_entity_subscripted {
  my ($self, $capture, $ns) = @_;
  $ns = defined $ns ? qq{$ns\:} : qr{\w+:};
  my $name = $self->re_nsname;
  my $sub = $self->re_subscript;
  my $body = qq{$name$sub*};
  if (defined $capture and $capture > 1) {
    qr{&($ns)($body);}xs;
  } else {
    my $re = qr{&$ns$body;}xs;
    $capture ? qr{($re)} : $re;
  }
}

# This cannot handle matching paren, of course;-).
sub re_subscript {
  my $name = shift->re_nsname;
  qr{[\[\(\{]
     [\w\.\-\+\$\[\]\{\}]*?
     [\}\)\]]
   |\. $name
   |\: [/\$\.\-\w]+
  }xs;
}

# more extended
sub re_entity_pathexpr {
  my ($self, $capture, $ns) = @_;
  $ns = $self->re_prefix($capture, $ns, '');
  my $body = qr{[:\.\w\$\-\+\*/%<>=\[\]\{\}\(,\)]+};
  if (defined $capture and $capture > 1) {
    qr{&$ns\b($body)?;}xs;
  } else {
    my $re = qr{&$ns\b$body;}xs;
    $capture ? qr{($re)} : $re;
  }
}

#
sub re_prefix {
  (my MY $self, my ($capture, $ns, $pre, $suf)) = @_;
  $ns = $$self{re_ns} unless defined $ns;
  $pre = '' unless defined $pre;
  $suf = '' unless defined $suf;
  if (defined $ns and $ns ne '') {
    $ns = "($ns)" if $capture > 1;
    qq{$pre$ns$suf};
  } else {
    ''
  }
}

1;
