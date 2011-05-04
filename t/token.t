use Test::More;
use Business::OnlinePayment;

my $tx = Business::OnlinePayment->new(
  'SagePay',
  'vendor' => 'airspace',
);
$tx->set_server('test');
$tx->content(
  'name_on_card' => 'Mr Test Test',
  'card_number' => '6759000000005462',
  'startdate' => '03/09',
  'expiration' => '03/15',
  'issue_number' => '',
  'cvv2' => 123,
  'type' => 'maestro',
);

$tx->token_action();
use Devel::Dwarn;Dwarn $tx->server_response;

done_testing()