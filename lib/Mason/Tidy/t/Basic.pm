package Mason::Tidy::t::Basic;
use Mason::Tidy;
use Test::More;
use strict;
use warnings;
use base qw(Test::Class);

sub tidy {
    my %params  = @_;
    my $source  = $params{source} or die "source required";
    my $desc    = $params{desc} or die "desc required";
    my $options = $params{options} || {};

    my $mt   = Mason::Tidy->new(%$options);
    my $dest = eval { $mt->tidy($source) };
    my $err  = $@;
    if ( my $expect_error = $params{expect_error} ) {
        like( $err, $expect_error, "got error - $desc" );
        is( $dest, undef, "no dest returned - $desc" );
    }
    else {
        is( $err, '', "no error - $desc" );
        is( trim($dest), trim( $params{expect} ), "expected content - $desc" );
    }
}

sub trim {
    my $str = $_[0];
    for ($str) { s/^\s+//; s/\s+$// }
    return $str;
}

sub test_perl_sections : Tests {
    tidy(
        desc   => 'init section',
        source => '
<%init>
my $form_data = delete( $m->req->session->{form_data} );
my @articles = @{ Blog::Article::Manager->get_articles( sort_by => "create_time DESC", limit => 5 ) };
</%init>
',
        expect => '
<%init>
  my $form_data = delete( $m->req->session->{form_data} );
  my @articles =
    @{ Blog::Article::Manager->get_articles( sort_by => "create_time DESC", limit => 5 ) };
</%init>
'
    );

    tidy(
        desc   => 'empty init section',
        source => '
<%init>

</%init>
',
        expect => '
<%init>
</%init>
'
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

sub test_perl_lines : Tests {
    tidy(
        desc   => 'perl lines',
        source => '
%if ($foo  )   {  
%my @articles = @{ Blog::Article::Manager->get_articles( sort_by => "create_time DESC", limit => 5 ) };
%    }  
',
        expect => '
% if ($foo) {
%   my @articles = @{ Blog::Article::Manager->get_articles( sort_by => "create_time DESC", limit => 5 ) };
% }
'
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
%   sub { uc( $_[0] ) } {{
%     $.Fobernate() {{
   This string will be trimmed, uppercased
   and fobernated
%     }}
%   }}
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
%   if ($bar) {
%     baz();
%   }
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
        desc   => 'indent_perl_block 4',
        source => $source,
        expect => '
<%perl>
  if ($foo) {
      $bar = 6;
  }
</%perl>
'
    );
}

sub test_errors : Tests {
    tidy(
        desc         => 'syntax error',
        source       => '% if ($foo) {',
        expect_error => qr/final indentation level/,
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
%   foreach my $line (@lines) {
<%perl>
  dothis();
  andthat();
</%perl>
  <li>
      <% 2 + ( 3 - 4 ) * 6 %>
  </li>
  <li><% foo( $.bar, $.baz, $.bleah ) %></li>
%   }
  </ul>
% }

% $.Filter( 3, 2 ) {{
some filtered text
% }}

<%method foo>
% if ( defined($bar) ) {
%   if ($write_list) {
even more text
%   }
% }
</%method>
'
    );
}

1;
