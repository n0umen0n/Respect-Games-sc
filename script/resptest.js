// SPDX-License-Identifier: MIT
(async () => {
  try {
    console.log('Starting Liquid Respect Distribution test script...');

    const accounts = await web3.eth.getAccounts();
    console.log('Accounts loaded:', accounts.length, 'accounts available');

    const deployerAccount = accounts[0];

    // Deploy LiquidRespectDistribution contract
    console.log('Deploying LiquidRespectDistribution contract...');
    const contractMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contracts/artifacts/LiquidRespectDistribution.json'));
    let liquidRespectContract = new web3.eth.Contract(contractMetadata.abi);
    liquidRespectContract = await liquidRespectContract.deploy({
      data: contractMetadata.data.bytecode.object,
      arguments: []
    }).send({ from: deployerAccount, gas: 3000000 });
    console.log('LiquidRespectDistribution deployed at:', liquidRespectContract.options.address);

    // Test cases
    const testCases = [
      {
        totalRespect: 1000000,
        groupRankings: [[1, 2, 3, 4, 5], [1, 2, 3, 4]]
      },
      {
        totalRespect: 500000,
        groupRankings: [[1, 2, 3], [1, 2, 3], [1, 2, 3]]
      },
      {
        totalRespect: 2000000,
        groupRankings: [[1, 2], [1, 2], [1, 2], [1, 2], [1, 2]]
      }
    ];

    for (let i = 0; i < testCases.length; i++) {
      const { totalRespect, groupRankings } = testCases[i];
      console.log(`\nTest Case ${i + 1}:`);
      console.log('Total Respect:', totalRespect);
      console.log('Group Rankings:', JSON.stringify(groupRankings));

      const distribution = await liquidRespectContract.methods.distributeRespect(totalRespect, groupRankings).call();
      console.log('Distribution:', distribution);

      const sumOfDistribution = await liquidRespectContract.methods.getSumOfDistribution(distribution).call();
      console.log('Sum of Distribution:', sumOfDistribution);

      // Verify that the sum of distribution matches the total respect
      const difference = Math.abs(parseInt(sumOfDistribution) - totalRespect);
      console.log('Difference from total respect:', difference);
      if (difference <= 1) { // Allow for a small rounding error
        console.log('Distribution is correct!');
      } else {
        console.log('Warning: Distribution sum does not match total respect');
      }

      // Log individual allocations
      let currentIndex = 0;
      for (let j = 0; j < groupRankings.length; j++) {
        console.log(`\nGroup ${j + 1} allocations:`);
        for (let k = 0; k < groupRankings[j].length; k++) {
          console.log(`  Rank ${k + 1}: ${distribution[currentIndex]}`);
          currentIndex++;
        }
      }
    }

    console.log('\nScript execution completed successfully.');
  } catch (error) {
    console.error('Error:', error.message);
    console.error('Error stack:', error.stack);
  }
})();