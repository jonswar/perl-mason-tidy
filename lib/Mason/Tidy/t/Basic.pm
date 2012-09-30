package Mason::Tidy::t::Basic;
use Mason::Tidy;
use Test::Class::Most parent => 'Test::Class';

sub tidy {
    my %params  = @_;
    my $source  = $params{source} or die "source required";
    my $expect  = $params{expect};
    my $options = { mason_version => 2, %{ $params{options} || {} } };
    my $desc    = $params{desc};
    ($desc) = ( ( caller(1) )[3] =~ /([^:]+$)/ ) if !$desc;

    $source =~ s/\\n/\n/g;
    if ( defined($expect) ) {
        $expect =~ s/\\n/\n/g;
        $expect .= "\n" if $expect !~ /\n$/;    # since masontidy enforces final newline
    }

    my $mt = Mason::Tidy->new( %$options, perltidy_argv => '--noprofile' );
    my $dest = eval { $mt->tidy($source) };
    my $err = $@;
    if ( my $expect_error = $params{expect_error} ) {
        like( $err, $expect_error, "got error - $desc" );
        is( $dest, undef, "no dest returned - $desc" );
    }
    else {
        is( $err,  '',      "no error - $desc" );
        is( $dest, $expect, "expected content - $desc" );
    }
}

sub trim {
    my $str = $_[0];
    return undef if !defined($str);
    for ($str) { s/^\s+//; s/\s+$// }
    return $str;
}

sub test_perl_sections : Tests {
    tidy(
        desc   => 'init section',
        source => '
<%init>
if($foo  )   {  
my @ids = (1,2);
    }  
</%init>
',
        expect => '
<%init>
if ($foo) {
    my @ids = ( 1, 2 );
}
</%init>
'
    );

    # This isn't ideal - would prefer it compressed to a single newline - but
    # both the <%init> and </%init> grab onto one of the newlines
    #
    tidy(
        desc   => 'empty init section',
        source => "<%init>\n\n\n\n</%init>",
        expect => "<%init>\n\n</%init>",
    );
}

sub test_mixed_sections : Tests {
    tidy(
        desc   => 'method',
        source => '
<%method foo>
%if (  $foo) {
content
%}
</%method>
',
        expect => '
<%method foo>
% if ($foo) {
content
% }
</%method>
'
    );

    tidy(
        desc   => 'empty method',
        source => '
<%method foo>
</%method>
',
        expect => '
<%method foo>
</%method>
'
    );
}

sub test_args : Tests {
    tidy(
        desc   => 'perl lines',
        source => '
<%args>
$a
@b
%c
$d => "foo"
@e => (1,2,3)
%f => (a=>5, b=>6)
</%args>
',
        expect => '
<%args>
$a
@b
%c
$d => "foo"
@e => (1,2,3)
%f => (a=>5, b=>6)
</%args>
'
    );
}

sub test_final_newline : Tests {
    tidy(
        desc   => 'one perl line with final newline',
        source => '% my $foo = 5;\n',
        expect => '% my $foo = 5;\n',
    );
    tidy(
        desc   => 'one perl line without final newline',
        source => '% my $foo = 5;',
        expect => '% my $foo = 5;\n',
    );
    tidy(
        desc   => 'two perl lines with final newline',
        source => '% my $foo = 5;\n% my $bar = 6;\n',
        expect => '% my $foo = 5;\n% my $bar = 6;\n',
    );
    tidy(
        desc   => 'two perl lines without final newline',
        source => '% my $foo = 5;\n% my $bar = 6;',
        expect => '% my $foo = 5;\n% my $bar = 6;\n',
    );
    tidy(
        desc   => 'two perl lines with two final newlines',
        source => '% my $foo = 5;\n% my $bar = 6;\n\n',
        expect => '% my $foo = 5;\n% my $bar = 6;\n',
    );
}

sub test_perl_lines_and_perl_blocks : Tests {
    tidy(
        desc   => 'perl lines',
        source => '
%my $d = 3;
<%perl>
if($foo  )   {
</%perl>
%my @ids = (1,2);
<%perl>
my $foo = 3;
if($bar) {
my $s = 9;
</%perl>
% my $baz = 4;
%}
%    }  
',
        expect => '
% my $d = 3;
<%perl>
  if ($foo) {
</%perl>
%     my @ids = ( 1, 2 );
<%perl>
      my $foo = 3;
      if ($bar) {
          my $s = 9;
</%perl>
%         my $baz = 4;
%     }
% }
'
    );
}

sub test_blocks_and_newlines : Tests {
    tidy(
        desc   => 'no newlines',
        source => "<%perl>my \$foo=5;</%perl>",
        expect => "<%perl>my \$foo=5;</%perl>"
    );
    tidy(
        desc   => 'newline before </%perl>',
        source => "<%perl>my \$foo=5;\n  </%perl>",
        expect => "<%perl>my \$foo=5;\n  </%perl>"
    );
    tidy(
        desc   => 'newline after <%perl>',
        source => "<%perl>\nmy \$foo=5;</%perl>",
        expect => "<%perl>\nmy \$foo=5;</%perl>"
    );
    tidy(
        desc   => 'newlines after <%perl> and before </%perl>',
        source => "<%perl>\nmy \$foo=5;\n</%perl>",
        expect => "<%perl>\n  my \$foo = 5;\n</%perl>"
    );
    tidy(
        desc   => 'double embedded newlines in <%perl>',
        source => '<%perl>\n\nmy $foo = 3;\n\nmy $bar = 4;\n\n</%perl>',
        expect => '<%perl>\n\n  my $foo = 3;\n\n  my $bar = 4;\n\n</%perl>',
    );
    tidy(
        desc   => 'triple embedded newlines in <%perl>',
        source => '<%perl>\n\n\nmy $foo = 3;\n\n\nmy $bar = 4;\n\n\n</%perl>',
        expect => '<%perl>\n\n\n  my $foo = 3;\n\n\n  my $bar = 4;\n\n\n</%perl>',
    );
    tidy(
        desc   => 'no newlines',
        source => "<%init>my \$foo=5;</%init>",
        expect => "<%init>my \$foo = 5;</%init>"
    );
    tidy(
        desc   => 'newline before </%init>',
        source => "<%init>my \$foo=5;\n  </%init>",
        expect => "<%init>my \$foo = 5;\n  </%init>"
    );
    tidy(
        desc   => 'newline after <%init>',
        source => "<%init>\nmy \$foo=5;</%init>",
        expect => "<%init>\nmy \$foo = 5;</%init>"
    );
    tidy(
        desc   => 'newlines after <%init> and before </%init>',
        source => "<%init>\nmy \$foo=5;\n</%init>",
        expect => "<%init>\nmy \$foo = 5;\n</%init>"
    );
    tidy(
        desc   => 'double embedded newlines in <%init>',
        source => '<%init>\n\nmy $foo = 3;\n\nmy $bar = 4;\n\n</%init>',
        expect => '<%init>\nmy $foo = 3;\nmy $bar = 4;\n</%init>',
    );
}

sub test_tags : Tests {
    tidy(
        desc   => 'subst tag',
        source => '<%$x%> text <%foo(5,6)%>',
        expect => '<% $x %> text <% foo( 5, 6 ) %>',
    );
    tidy(
        desc   => 'comp call tag',
        source => '<&/foo/bar,a=>5,b=>6&> text <&  $comp_path, str=>"foo"&>',
        expect => '<& /foo/bar, a => 5, b => 6 &> text <& $comp_path, str => "foo" &>',
    );
}

sub test_filter_invoke : Tests {
    tidy(
        desc   => 'filter invoke',
        source => '
%$.Trim(3,17) {{
%sub {uc($_[0]  )} {{
%$.Fobernate() {{
   This string will be trimmed, uppercased
   and fobernated
% }}
%}}
%   }}
',
        expect => '
% $.Trim( 3, 17 ) {{
%     sub { uc( $_[0] ) } {{
%         $.Fobernate() {{
   This string will be trimmed, uppercased
   and fobernated
%         }}
%     }}
% }}
'
    );
}

sub test_filter_decl : Tests {
    tidy(
        desc   => 'Mason 1 filter declaration (no arg)',
        source => '
Hi

<%filter>
if (/abc/) {
s/abc/def/;
}
</%filter>
',
        expect => '
Hi

<%filter>
if (/abc/) {
    s/abc/def/;
}
</%filter>
'
    );

    tidy(
        desc   => 'Mason 2 filter declaration (w/ arg)',
        source => '
<%filter Item ($class)>
<li class="<%$class%>">
%if (my $x = $yield->()) {
<% $x %>
%}
</li>
</%filter>
',
        expect => '
<%filter Item ($class)>
<li class="<% $class %>">
% if ( my $x = $yield->() ) {
<% $x %>
% }
</li>
</%filter>
'
    );
}

sub test_perltidy_argv : Tests {
    tidy(
        desc   => 'default indent 2',
        source => '
% if ($foo) {
% if ($bar) {
% baz();
% }
% }
',
        expect => '
% if ($foo) {
%     if ($bar) {
%         baz();
%     }
% }
'
    );
    tidy(
        desc    => 'perltidy_line_argv = -i=2',
        options => { perltidy_line_argv => '-i=2' },
        source  => '
% if ($foo) {
% if ($bar) {
% baz();
% }
% }
',
        expect => '
% if ($foo) {
%   if ($bar) {
%     baz();
%   }
% }
'
    );
}

sub test_single_line_block : Tests {
    tidy(
        desc   => 'indent_perl_block 0',
        source => '
<%perl>my $foo = 5;</%perl>
',
        expect => '
<%perl>my $foo = 5;</%perl>
'
    );
}

sub test_indent_perl_block : Tests {
    my $source = '
<%perl>
    if ($foo) {
$bar = 6;
  }
</%perl>
';
    tidy(
        desc    => 'indent_perl_block 0',
        options => { indent_perl_block => 0 },
        source  => $source,
        expect  => '
<%perl>
if ($foo) {
    $bar = 6;
}
</%perl>
'
    );
    tidy(
        desc   => 'indent_perl_block 2 (default)',
        source => $source,
        expect => '
<%perl>
  if ($foo) {
      $bar = 6;
  }
</%perl>
'
    );

    tidy(
        desc    => 'indent_perl_block 4',
        options => { indent_perl_block => 4 },
        source  => $source,
        expect  => '
<%perl>
    if ($foo) {
        $bar = 6;
    }
</%perl>
'
    );
}

sub test_indent_block : Tests {
    my $source = '
<%init>

    if ($foo) {
$bar = 6;
  }

</%init>
';
    tidy(
        desc   => 'indent_block 0 (default)',
        source => $source,
        expect => '
<%init>
if ($foo) {
    $bar = 6;
}
</%init>
'
    );
    tidy(
        desc    => 'indent_block 2',
        options => { indent_block => 2 },
        source  => $source,
        expect  => '
<%init>
  if ($foo) {
      $bar = 6;
  }
</%init>
'
    );
}

sub test_errors : Tests {
    tidy(
        desc         => 'syntax error',
        source       => '% if ($foo) {',
        expect_error => qr/final indentation level/,
    );
    tidy(
        desc         => 'no matching close block',
        source       => "<%init>\nmy \$foo = bar;</%ini>",
        expect_error => qr/no matching end tag/,
    );
}

sub test_random_bugs : Tests {
    tidy(
        desc    => 'final double brace (mason 1)',
        options => { mason_version => 1 },
        source  => '
% if ($foo) {
% if ($bar) {
% }}
',
        expect => '
% if ($foo) {
%     if ($bar) {
% }}
'
    );
}

sub test_comprehensive : Tests {
    tidy(
        desc   => 'comprehensive',
        source => '
some text

% if ( $contents || $allow_empty ) {
  <ul>
% foreach my $line (@lines) {
<%perl>
dothis();
andthat();
</%perl>
  <li>
      <%2+(3-4)*6%>
  </li>
  <li><%  foo($.bar,$.baz,  $.bleah)   %></li>
% }
  </ul>
% }

%  $.Filter(3,2) {{  
some filtered text
%}}

<&footer,color=>"blue",height  =>  3&>

<%method foo>
%if(defined($bar)) {
% if  ( $write_list) {
even more text
%}
% }
</%method>
',
        expect => '
some text

% if ( $contents || $allow_empty ) {
  <ul>
%     foreach my $line (@lines) {
<%perl>
          dothis();
          andthat();
</%perl>
  <li>
      <% 2 + ( 3 - 4 ) * 6 %>
  </li>
  <li><% foo( $.bar, $.baz, $.bleah ) %></li>
%     }
  </ul>
% }

% $.Filter( 3, 2 ) {{
some filtered text
% }}

<& footer, color => "blue", height => 3 &>

<%method foo>
% if ( defined($bar) ) {
%     if ($write_list) {
even more text
%     }
% }
</%method>
'
    );
}

1;
