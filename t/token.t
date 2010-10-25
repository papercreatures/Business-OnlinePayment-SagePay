use Test::More;
use Business::OnlinePayment;

my $tx = Business::OnlinePayment->new(
  'SagePay',
  'vendor' => 'airspace',
);
$tx->set_server('simulator');
$tx->content(
  'name_on_card' => 'Mr Test Test',
  'card_number' => '0000 0000 0000 0000',
  'startdate' => '03/09',
  'expiration' => '03/20',
  'issue_number' => 3,
  'cvv2' => 111,
  'type' => 'maestro',
);

$tx->token_action();
use Devel::Dwarn;Dwarn $tx->server_response;

done_testing()