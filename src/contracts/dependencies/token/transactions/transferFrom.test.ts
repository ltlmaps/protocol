import { createQuantity } from '@melonproject/token-math/quantity';
import { Address } from '@melonproject/token-math/address';
import { initTestEnvironment } from '~/utils/environment/initTestEnvironment';
import { approve } from '../transactions/approve';
import { transferFrom } from '../transactions/transferFrom';
import { deployToken } from '../transactions/deploy';
import { getToken } from '../calls/getToken';

const shared: any = {};

beforeAll(async () => {
  shared.env = await initTestEnvironment();
  shared.address = await deployToken(shared.env);
  shared.token = await getToken(shared.env, shared.address);
});

test('transferFrom', async () => {
  const accounts = await shared.env.eth.getAccounts();
  const howMuch = createQuantity(shared.token, '1000000000000000000');

  await approve(shared.env, { howMuch, spender: new Address(accounts[0]) });

  const receipt = await transferFrom(shared.env, {
    from: new Address(accounts[0]),
    howMuch,
    to: new Address(accounts[1]),
  });

  expect(receipt).toBeTruthy();
});
