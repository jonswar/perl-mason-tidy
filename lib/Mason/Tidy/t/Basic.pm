package Mason::Tidy::t::Basic;
use Mason::Tidy;
use Test::More;
use strict;
use warnings;
use base qw(Test::Class);

sub tidy {
    my %params  = @_;
    my $source  = $params{source} or die "source required";
    my $expect  = $params{expect} or die "expect required";
    my $desc    = $params{desc} or die "desc required";
    my $options = $params{options} || {};

    my $mt   = Mason::Tidy->new(%$options);
    my $dest = $mt->tidy($source);
    is( trim($dest), trim($expect), $desc );
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
        desc    => 'indent 4',
        options => { perltidy_argv => '-fnl -i=4' },
        source  => '
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
  
some more text

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
  
some more text

<%method foo>
% if ( defined($bar) ) {
%   if ($write_list) {
  even more text
%   }
% }
</%method>'
    );
}

1;