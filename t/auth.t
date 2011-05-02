#!/usr/bin/perl

use FindBin '$Bin';
use lib "$Bin/lib";
use threads;

use Test::More;
use Business::OnlinePayment;
use Test::Business::OnlinePayment::SagePay qw(create_transaction create_simple_web_server);

BEGIN {
    if (defined $ENV{SAGEPAY_VENDOR}) {
        plan tests => 5;
    }
    else {
        plan skip_all => 'SAGEPAY_VENDOR environemnt variable not defined}';
    }

    use_ok 'Business::OnlinePayment::SagePay';
}

my $tx = Business::OnlinePayment->new(
    'SagePay',
    vendor      => $ENV{SAGEPAY_VENDOR},
    protocol    => 2.23,
    currency    => 'gbp',
);
ok($tx, 'Transaction object');

$tx->content( create_transaction() );

$tx->set_server('simulator');

ok($tx->submit, 'Transaction submitted');

ok($tx->is_success, 'Transaction success');

SKIP: {
    skip 'SAGEPAY_SIMULATOR_3DSEC environment variable not defined', 1 
        unless defined($ENV{SAGEPAY_SIMULATOR_3DSEC}); 

    is($tx->result_code, '3DAUTH', '3DSecure response');

    my $thread = threads->create(\&create_simple_web_server);

use LWP::UserAgent;
use Storable 'thaw';
use Data::Dumper;

    my $ua = LWP::UserAgent->new;
    my $response = $ua->get('http://localhost:15100?a=1&b=2');
    my $result = thaw( $response->content );

    print Dumper $result;

    $thread->detach;
}

done_testing();

