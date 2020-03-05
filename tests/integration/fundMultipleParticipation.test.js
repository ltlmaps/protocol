/*
 * @file Tests multiple participations in a fund from multiple investors
 *
 * @test A user can only have 1 pending investment at a time
 * @test A second user can simultaneously invest (with a second default token)
 * @test A third user can simultaneously invest (with a newly approved token)
 * @test Multiple pending investment requests can all be exectuted
 * @test Request can be executed through Engine, burning MLN
 * @test Changing incentive does not affect incentive attached to an existing request
 */

import web3 from '~/deploy/utils/get-web3';
import { BN, toWei } from 'web3-utils';
import { call, send } from '~/deploy/utils/deploy-contract';
import { partialRedeploy } from '~/deploy/scripts/deploy-system';
import { CONTRACT_NAMES } from '~/tests/utils/constants';
import { BNExpMul } from '~/tests/utils/BNmath';
import { setupFundWithParams } from '~/tests/utils/fund';
import getAccounts from '~/deploy/utils/getAccounts';
import { delay } from '~/tests/utils/time';

let deployer, manager, investor1, investor2, investor3;
let defaultTxOpts, managerTxOpts;
let investor1TxOpts, investor2TxOpts, investor3TxOpts;

beforeAll(async () => {
  [
    deployer,
    manager,
    investor1,
    investor2,
    investor3
  ] = await getAccounts();

  defaultTxOpts = { from: deployer, gas: 8000000 };
  managerTxOpts = { ...defaultTxOpts, from: manager };
  investor1TxOpts = { ...defaultTxOpts, from: investor1 };
  investor2TxOpts = { ...defaultTxOpts, from: investor2 };
  investor3TxOpts = { ...defaultTxOpts, from: investor3 };
});

describe('Fund 1: Multiple investors buying shares with different tokens', () => {
  let amguAmount, shareSlippageTolerance;
  let wantedShares1, wantedShares2, wantedShares3, wantedShares4;
  let daiToEthRate, mlnToEthRate, wethToEthRate;
  let dai, mln, priceSource, weth;
  let registry, fund, engine, engineAdapter;

  beforeAll(async () => {
    const deployed = await partialRedeploy([CONTRACT_NAMES.VERSION]);
    const contracts = deployed.contracts;
    registry = contracts[CONTRACT_NAMES.REGISTRY];
    engine = contracts[CONTRACT_NAMES.ENGINE];
    engineAdapter = contracts[CONTRACT_NAMES.ENGINE_ADAPTER];
    dai = contracts.DAI;
    mln = contracts.MLN;
    weth = contracts.WETH;
    priceSource = contracts.TestingPriceFeed;
    const version = contracts.Version;

    // Set initial prices to be predictably the same as prices when updated again later
    wethToEthRate = toWei('1', 'ether');
    mlnToEthRate = toWei('0.5', 'ether');
    daiToEthRate = toWei('0.005', 'ether');
    await send(
      priceSource,
      'update',
      [
        [weth.options.address, mln.options.address, dai.options.address],
        [wethToEthRate, mlnToEthRate, daiToEthRate],
      ],
      defaultTxOpts
    );

    fund = await setupFundWithParams({
      defaultTokens: [mln.options.address, weth.options.address],
      initialInvestment: {
        contribAmount: toWei('1', 'ether'),
        investor: manager,
        tokenContract: weth
      },
      exchanges: [engine.options.address],
      exchangeAdapters: [engineAdapter.options.address],
      manager,
      quoteToken: weth.options.address,
      version
    });

    amguAmount = toWei('.01', 'ether');
    wantedShares1 = toWei('1', 'ether');
    wantedShares2 = toWei('2', 'ether');
    wantedShares3 = toWei('1.5', 'ether');
    wantedShares4 = toWei('0.5', 'ether');
    shareSlippageTolerance = new BN(toWei('0.0001', 'ether')); // 0.01%
  });

  test('A user can have only one pending investment request', async () => {
    const { accounting, participation } = fund;

    const offerAsset = weth.options.address;
    const expectedOfferAssetCost = new BN(
      await call(
        accounting,
        'getShareCostInAsset',
        [wantedShares1, offerAsset]
      )
    );
    const offerAssetMaxQuantity = BNExpMul(
      expectedOfferAssetCost,
      new BN(toWei('1', 'ether')).add(shareSlippageTolerance)
    ).toString();

    // Investor 1 - weth
    await send(weth, 'transfer', [investor1, offerAssetMaxQuantity], defaultTxOpts);
    await send(
      weth,
      'approve',
      [participation.options.address, offerAssetMaxQuantity],
      investor1TxOpts
    );
    await send(
      participation,
      'requestInvestment',
      [wantedShares1, offerAssetMaxQuantity, weth.options.address],
      { ...investor1TxOpts, value: amguAmount }
    );

    // Investor 1 - weth
    await send(weth, 'transfer', [investor1, offerAssetMaxQuantity], defaultTxOpts);
    await send(
      weth,
      'approve',
      [participation.options.address, offerAssetMaxQuantity],
      investor1TxOpts
    );
    await expect(
      send(
        participation,
        'requestInvestment',
        [wantedShares1, offerAssetMaxQuantity, offerAsset],
        { ...investor1TxOpts, value: amguAmount }
      )
    ).rejects.toThrowFlexible('Only one request can exist at a time');
  });

  test('Investment request allowed for second user with another default token', async () => {
    const { accounting, participation } = fund;

    const offerAsset = mln.options.address;
    const expectedOfferAssetCost = new BN(
      await call(
        accounting,
        'getShareCostInAsset',
        [wantedShares2, offerAsset]
      )
    );
    const offerAssetMaxQuantity = BNExpMul(
      expectedOfferAssetCost,
      new BN(toWei('1', 'ether')).add(shareSlippageTolerance)
    ).toString();

    // Investor 2 - mln
    await send(mln, 'transfer', [investor2, offerAssetMaxQuantity], defaultTxOpts);
    await send(
      mln,
      'approve',
      [participation.options.address, offerAssetMaxQuantity],
      investor2TxOpts
    );
    await send(
      participation,
      'requestInvestment',
      [wantedShares2, offerAssetMaxQuantity, offerAsset],
      { ...investor2TxOpts, value: amguAmount }
    );
  });

  test('Investment request allowed for third user with approved token', async () => {
    const { accounting, participation } = fund;

    const offerAsset = dai.options.address;
    const expectedOfferAssetCost = new BN(
      await call(
        accounting,
        'getShareCostInAsset',
        [wantedShares3, offerAsset]
      )
    );
    const offerAssetMaxQuantity = BNExpMul(
      expectedOfferAssetCost,
      new BN(toWei('1', 'ether')).add(shareSlippageTolerance)
    ).toString();

    // Investor 3 - dai
    await send(dai, 'transfer', [investor3, offerAssetMaxQuantity], defaultTxOpts);
    await send(
      dai,
      'approve',
      [participation.options.address, offerAssetMaxQuantity],
      investor3TxOpts
    );

    // Investment asset must be enabled
    await expect(
      send(
        participation,
        'requestInvestment',
        [wantedShares3, offerAssetMaxQuantity, offerAsset],
        { ...investor3TxOpts, value: amguAmount }
      )
    ).rejects.toThrowFlexible("Investment not allowed in this asset");

    await send(participation, 'enableInvestment', [[offerAsset]], managerTxOpts);

    await send(
      participation,
      'requestInvestment',
      [wantedShares3, offerAssetMaxQuantity, offerAsset],
      { ...investor3TxOpts, value: amguAmount }
    )
  });

  test('Multiple pending investments can be executed', async () => {
    const { participation, shares } = fund;

    // Need price update before participation executed
    await delay(1000);

    await send(
      priceSource,
      'update',
      [
        [weth.options.address, mln.options.address, dai.options.address],
        [wethToEthRate, mlnToEthRate, daiToEthRate],
      ],
      defaultTxOpts
    );

    await send(
      participation,
      'executeRequest',
      [],
      investor1TxOpts
    );
    const investor1Shares = await call(shares, 'balanceOf', [investor1]);
    expect(investor1Shares).toEqual(wantedShares1);

    await send(
      participation,
      'executeRequest',
      [],
      investor2TxOpts
    );
    const investor2Shares = await call(shares, 'balanceOf', [investor2]);
    expect(investor2Shares).toEqual(wantedShares2);

    await send(
      participation,
      'executeRequest',
      [],
      investor3TxOpts
    );
    const investor3Shares = await call(shares, 'balanceOf', [investor3]);
    expect(investor3Shares).toEqual(wantedShares3);
  });

  test('Investment request allowed (with incentive) after previous request executed', async () => {
    const { accounting, participation } = fund;

    const incentiveAmount = '10000000000000';
    await send(registry, 'setIncentive', [incentiveAmount], defaultTxOpts);

    const offerAsset = weth.options.address;
    const expectedOfferAssetCost = new BN(
      await call(
        accounting,
        'getShareCostInAsset',
        [wantedShares4, offerAsset]
      )
    );
    const offerAssetMaxQuantity = BNExpMul(
      expectedOfferAssetCost,
      new BN(toWei('1', 'ether')).add(shareSlippageTolerance)
    ).toString();

    // Investor 1 - weth
    await send(weth, 'transfer', [investor1, offerAssetMaxQuantity], defaultTxOpts);
    await send(
      weth,
      'approve',
      [participation.options.address, offerAssetMaxQuantity],
      investor1TxOpts
    );
    await send(
      participation,
      'requestInvestment',
      [wantedShares4, offerAssetMaxQuantity, weth.options.address],
      { ...investor1TxOpts, value: new BN(amguAmount).add(new BN(incentiveAmount)) }
    );
  });

  test('Request can be executed through Engine, burning MLN', async () => {
    const { participation, shares } = fund;

    // Need price update before participation executed
    await delay(1000);

    await send(
      priceSource,
      'update',
      [
        [weth.options.address, mln.options.address, dai.options.address],
        [wethToEthRate, mlnToEthRate, daiToEthRate],
      ],
      defaultTxOpts
    );

    // Unauthorized address cannot call executeRequestFor
    await expect(
      send(
        participation,
        'executeRequestFor',
        [investor1],
        investor3TxOpts
    )).rejects.toThrowFlexible('This can only be called through the Engine');

    // Address without enough MLN is unable to execute another's request
    expect((await call(mln, 'balanceOf', [investor3])).toString()).toBe('0');
    await expect(
      send(
        engine,
        'executeRequestAndBurnMln',
        [participation.options.address, investor1],
        investor3TxOpts
    )).rejects.toThrowFlexible('executeRequestAndBurnMln: Sender does not have enough MLN');

    // Set up executor (investor3) with enough MLN
    const incentiveFromRequest = new BN(
      await call(participation, 'getRequestIncentive', [investor1])
    );
    const mlnRequiredToExecute = new BN(
      await call(engine, 'mlnRequiredForIncentiveAmount', [incentiveFromRequest.toString()])
    );
    await send(mln, 'transfer', [investor3, mlnRequiredToExecute.toString()], defaultTxOpts);

    // Attempting to execute without approving MLN should fail
    await expect(
      send(
        engine,
        'executeRequestAndBurnMln',
        [participation.options.address, investor1],
        investor3TxOpts
      )
    ).rejects.toThrowFlexible();

    // Approving sufficient MLN and executing should work
    await send(
      mln,
      'approve',
      [engine.options.address, mlnRequiredToExecute.toString()],
      investor3TxOpts
    );

    const preInvestor1Shares = new BN(await call(shares, 'balanceOf', [investor1]));
    const preMlnTotalSupply = new BN(await call(mln, 'totalSupply'));
    const preParticipationEth = new BN(await web3.eth.getBalance(participation.options.address));
    const preExecutorEth = new BN(await web3.eth.getBalance(investor3));
    const preExecutorMln = new BN(await call(mln, 'balanceOf', [investor3]));

    const gasPrice = await web3.eth.getGasPrice();
    const receipt = await send(
      engine,
      'executeRequestAndBurnMln',
      [participation.options.address, investor1],
      {...investor3TxOpts, gasPrice}
    );
    const executeTxCost = new BN(gasPrice).mul(new BN(receipt.gasUsed));

    const postInvestor1Shares = new BN(await call(shares, 'balanceOf', [investor1]));
    const postMlnTotalSupply = new BN(await call(mln, 'totalSupply'));
    const postParticipationEth = new BN(await web3.eth.getBalance(participation.options.address));
    const postExecutorMln = new BN(await call(mln, 'balanceOf', [investor3]));
    const postExecutorEth = new BN(await web3.eth.getBalance(investor3));

    expect(postInvestor1Shares).bigNumberEq(new BN(preInvestor1Shares).add(new BN(wantedShares4)));
    expect(postMlnTotalSupply).bigNumberEq(preMlnTotalSupply.sub(mlnRequiredToExecute));
    expect(postParticipationEth).bigNumberEq(preParticipationEth.sub(incentiveFromRequest));
    expect(postExecutorMln).bigNumberEq(preExecutorMln.sub(mlnRequiredToExecute));
    expect(postExecutorEth).bigNumberEq(
      new BN(preExecutorEth.add(incentiveFromRequest)).sub(executeTxCost)
    );
  });

  test('Changing incentive does not affect existing request', async () => {
    const { participation } = fund;

    const wethInvestAmount = 10000000;
    const preUpdateIncentive = new BN(await call(registry, 'incentive'));

    await send(weth, 'transfer', [investor1, wethInvestAmount], defaultTxOpts);
    await send(
      weth,
      'approve',
      [participation.options.address, wethInvestAmount],
      investor1TxOpts
    );
    await send(
      participation,
      'requestInvestment',
      [wethInvestAmount, wethInvestAmount, weth.options.address],
      { ...investor1TxOpts, value: amguAmount }
    );
    
    const newIncentive = new BN(preUpdateIncentive.mul(new BN('2')));
    await send(registry, 'setIncentive', [newIncentive.toString()], defaultTxOpts);
    const postUpdateIncentive = new BN(await call(registry, 'incentive'));

    expect(postUpdateIncentive).bigNumberEq(newIncentive);
   
    const incentiveFromRequest = new BN(await call(participation, 'getRequestIncentive', [investor1]));

    expect(incentiveFromRequest).bigNumberEq(preUpdateIncentive);
  });
});
