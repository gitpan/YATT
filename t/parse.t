#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*-
use strict;
use warnings FATAL => qw(all);
use Test::More no_plan => 1;
use Test::Differences;

use FindBin;
use lib "$FindBin::Bin/..";
require YATT::LRXML::Parser;
use YATT::LRXML::Node;

use Data::Dumper;
sub dumper {
  Data::Dumper->new(\@_)->Terse(1)->Indent(0)->Dump;
}

my $example = 1;
{
  my $parser = new YATT::LRXML::Parser(namespace => [qw(yatt perl)]);

  is_deeply(scalar $parser->parse_entities('foo&perl:var.bar;baz', 0)
	    , [TEXT_TYPE, undef
	       ,'foo'
	       , $parser->create_node(entity => 'perl', ':var.bar')
	       , 'baz']
	    , 'attvalue');

  is_deeply(scalar $parser->parse_entities('foo&perl:var.bar{$baz+};baz', 0)
	    , [TEXT_TYPE, undef
	       , 'foo'
	       , $parser->create_node(entity => 'perl', ':var.bar{$baz+}')
	       , 'baz' ]
	    , 'attvalue: with dot/curly subscript');

  is_deeply(scalar $parser->parse_entities('q=&perl:_[1].param(q);<br/>', 0)
	    , [TEXT_TYPE, undef
	       , 'q='
	       , $parser->create_node(entity => 'perl', ':_[1].param(q)')
	       , '<br/>']
	    , 'attvalue: with bracket/funcall subscript');

  is_deeply(scalar $parser->parse_entities('&perl:bar;', 0)
	    , $parser->create_node(entity => 'perl', ':bar')
	    , 'attvalue: entity only');

  is_deeply(scalar $parser->parse_entities('&perl:bar;baz', 0)
	    , [TEXT_TYPE, undef
	       , $parser->create_node(entity => 'perl', ':bar')
	       , 'baz',
	      ]
	    , 'attvalue: missing leading text');

  my $src = q(
<html>
<body>
<?perl my $user = $CGI.param("user"); ?>
<!--#perl comment -->
<h2>Welcom &perl:user;</h2>
</body>
</html>
);

  $parser = YATT::LRXML::Parser->new(namespace => [qw(yatt perl)]);
  {
    use Carp;
    local $SIG{__DIE__} = sub {
      confess(@_);
    };
    $parser->parse_string($src);
  }
  is $parser->tokens->[1]
    , '<?perl my $user = $CGI.param("user"); ?>'
    , "ex$example. Parser. pi";

#XXX:  is $parser->tree->type_realname
#XXX:    , 'root_element'
#XXX:    , "ex$example. \$tree is root_element";

  is $parser->tree->stringify, $src, "ex$example.  round trip";

  #----------------------------------------
  $example++;
  $src = <<'END';
<html>
<body>
<?perl &perl:varname; ?>
<!--#perl comment
 <perl:tag> ... </perl:tag>
-->
<!--foo bar-->
<h2>Welcom &perl:user;</h2>
</body>
</html>
END

  $parser->parse_string($src);
  my $tree = $parser->tree;
  print "tokens == \n", Dumper(scalar $parser->tokens), "\n" if $ENV{VERBOSE};
  print "tree == \n", Dumper($tree), "\n" if $ENV{VERBOSE};

  if ($ENV{VERBOSE}) {
    my $path = $parser->scanner(undef);
    my $i = 0;
    while ($path->readable) {
      print "read[$i](", $path->read, ")\n";
      $i++;
    }
    is $i, 7, "ex$example. number of feedable feeds.";
  }
  is $tree->size, 7, "ex$example. size of parsed tree";

  is $tree->stringify, $src, "ex$example.  round trip";

  #----------------------------------------
  $example++;
  $src = <<'END';
<html>
<body>
<?perlZZ &perlZZ:varname; ?>
<!--#perlZZ comment
 <perlZZ:tag> ... </perlZZ:tag>
-->
<perlZZ:tag> ... </perlZZ:tag>
<!--foo bar-->
<h2>Welcom &perlZZ:user;</h2>
</body>
</html>
END

  $parser->parse_string($src);
  $tree = $parser->tree;
  print "tokens == \n", Dumper(scalar $parser->tokens), "\n" if $ENV{VERBOSE};
  print "tree == \n", Dumper($tree), "\n" if $ENV{VERBOSE};

  is $tree->size, 1, "ex$example. size of parsed tree";

  is $tree->stringify, $src, "ex$example.  round trip";

  #----------------------------------------
  is $parser->parse_string('<input type=radio checked>')->stringify
    , q(<input type=radio checked />), q(<input type=radio checked />);

  #----------------------------------------

  $example++;
  $src = <<'END';
header
<form>
<table>
<perl:foreach my=row list='1..8, &perl:param:FOO;'>
<tr>
<perl:foreach my=col list='1..8, &perl:param:BAR;'>
<td><input type=radio name='q&perl:var:row;' value="&perl:var:col;" /> &perl:var:col;</td>
</perl:foreach>
</tr>
  <:perl:join />と</perl:foreach>
</table>
</form>
footer
END

  $parser->parse_string($src);
  $tree = $parser->tree;
  print "tokens == \n", Dumper(scalar $parser->tokens), "\n" if $ENV{VERBOSE};
  print "tree == \n", Dumper($tree), "\n" if $ENV{VERBOSE};

  if ($ENV{VERBOSE}) {
    my $path = $parser->scanner(undef);
    my $i = 0;
    while ($path->readable) {
      print "read[$i](", $path->read, ")\n";
      $i++;
    }
    is $i, 3, "ex$example. number of feedable feeds.";
  }
  is $tree->size, 3, "ex$example. size of parsed tree";

  eq_or_diff($tree->stringify, $src, "ex$example.  round trip");
  # タグの対応エラーを検出し、その行番号が一致していることを確認せよ。

  # foo='\'' を確認せよ

  #----------------------------------------

  $example++;
  $src = <<'END';
header
<form>
<perl:if var=q value=1>foo
<:perl:else var=q value=2 />bar
<:perl:else var=q value=3 />baz
<:perl:else />bang
</perl:if>
</form>
footer
END

  $parser->parse_string($src);
  $tree = $parser->tree;
  print "tokens == \n", Dumper(scalar $parser->tokens), "\n" if $ENV{VERBOSE};
  print "tree == \n", Dumper($tree), "\n" if $ENV{VERBOSE};

  is $tree->size, 3, "ex$example. size of parsed tree";

  is $tree->stringify, $src, "ex$example. round trip.";

  #----------------------------------------
  my $elem = $parser->parse_string('<form><input name=q value=v></form>');
  # is(($elem)->open->type_realname, 'form_element' , 'is form_element');

  #XXX: is($elem->open->open->get_name, 'form', 'is <form>');
}

{
  $example++;
  my $parser = YATT::LRXML::Parser->new(namespace => [qw(yatt perl)]
				       , debug => $ENV{DEBUG} ? 1 : 0);
  # stringify は通常 \s+ を ' ' にするので、一致検査のための前処理が必要。
  my $tree = $parser->parse_string(map {s/\\\n\s*/ /g; $_} my $src = <<'END');
<!yatt:widget foo1 nameonly2 "valueonly3"\
  -- Here is comment ! --\
 name4=value name5='value' name6="value"\
 name7=type|default name8=type?default name9="type/default"\
  --
    more more comment
  --\
 %yatt:foo10(bar=baz,bang=hoe);\
 [body11 name11_1=text1 name11_2= value2 ]\
 [  title12 name12_1=text name12_2=value2]>
body
END

  is $tree->open->size, 14, "ex$example. arg_decls size";
  is $tree->stringify, (map {
    # s/\n//g;
    s/\s+\]/\]/g;
    s/\[\s+/\[/g;
    s/\s*=\s*/=/g;
    # s/\s+--(.*?)--\s+/ --$1-- /gs;
    $_
  } $src)[0], "ex$example. round trip.";
}

my $src1 = <<'END';
<h2>&perl:title;</h2>
<ul>
<perl:foreach my=x list="@_">
<li>&perl:x; <perl:foobar y=8 x=3 /></li>
</perl:foreach>
</ul>
<:perl:widget foobar x=hoehoe y=bar />
<h2>&perl:x;-&perl:y;</h2>
<:perl:widget baz z w />
<h2>&perl:z;-&perl:w;</h2>
END

if (0) { # XXX:
  my $tree = new YATT::LRXML(string => $src1, filename => $0);
  print Dumper($tree) if $ENV{DEBUG};

  is $tree->size, 17, 'LRXML is correctly parsed';

  is $tree->stringify, $src1, 'LRXML round trip';

}

if (0) { # XXX:
  my $parser = new YATT::LRXML::Parser;
  my $html
    = q{<perl:foo
&perl:var;
my:foo
my:bar='BAR'
><:perl:baz>BAZ</:perl:baz>bang</perl:foo>};
  my @children = $parser->parse_string($html)->tree->children(0)->children;
  my $i = 0;
  is_deeply [$children[$i++]->get_name_value], [undef, '&perl:var;']
    , 'unnamed bare att';

  is_deeply [$children[$i++]->get_name_value], ['my:foo', undef]
    , 'bare nsname attname';

  is_deeply [$children[$i++]->get_name_value], ['my:bar', 'BAR']
    , 'nsname attname = value';

  is join("=", $children[$i]->get_name
	  , $children[$i]->get_value->stringify)
    , "baz=BAZ", 'element attr';
}

if (0)
{
  print YATT::Translator::Perl->from_string($src1, filename => $0)
    ->translate_as_subs_to(qw(print index));

#  print YATT::Translator::JavaScript->new($tree)
#    ->translate_as_function('index');
}
