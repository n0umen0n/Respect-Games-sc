// SPDX-License-Identifier: MIT
(async () => {
  try {
    console.log('Starting Community Governance test script...');

    const accounts = await web3.eth.getAccounts();
    console.log('Accounts loaded:', accounts.length, 'accounts available');

    const deployerAccount = accounts[0];
    const userAccounts = accounts.slice(1, 14); // Use 10 user accounts

    // Helper function to log events
    const logEvents = async (contract, eventName) => {
      const events = await contract.getPastEvents(eventName, {
        fromBlock: 0,
        toBlock: 'latest'
      });
      console.log(`${eventName} events:`, events.map(e => e.returnValues));
    };

    // Helper function to log community state
    async function logCommunityState(communityId) {
      const communityProfile = await profilesContract.methods.getCommunityProfile(communityId).call();
      console.log(`Community ${communityId} state:`, communityProfile[5] == "0" ? "ContributionSubmission" : "ContributionRanking");
      console.log(`Community ${communityId} event count:`, communityProfile[6]);
    }

    // Deploy CommunityGovernanceProfiles contract
    console.log('Deploying CommunityGovernanceProfiles contract...');
    const profilesMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contracts/artifacts/CommunityGovernanceProfiles.json'));
    let profilesContract = new web3.eth.Contract(profilesMetadata.abi);
    profilesContract = await profilesContract.deploy({
      data: profilesMetadata.data.bytecode.object,
      arguments: []
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceProfiles deployed at:', profilesContract.options.address);

    // Deploy CommunityGovernanceContributions contract
    console.log('Deploying CommunityGovernanceContributions contract...');
    const contributionsMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contracts/artifacts/CommunityGovernanceContributions.json'));
    let contributionsContract = new web3.eth.Contract(contributionsMetadata.abi);
    contributionsContract = await contributionsContract.deploy({
      data: contributionsMetadata.data.bytecode.object,
      arguments: [profilesContract.options.address]
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceContributions deployed at:', contributionsContract.options.address);

    // Deploy CommunityGovernanceRankings contract
    console.log('Deploying CommunityGovernanceRankings contract...');
    const rankingsMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contracts/artifacts/CommunityGovernanceRankings.json'));
    let rankingsContract = new web3.eth.Contract(rankingsMetadata.abi);
    rankingsContract = await rankingsContract.deploy({
      data: rankingsMetadata.data.bytecode.object,
      arguments: [contributionsContract.options.address, profilesContract.options.address]
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceRankings deployed at:', rankingsContract.options.address);

    // Set Rankings contract in Profiles contract
    await profilesContract.methods.setRankingsContract(rankingsContract.options.address).send({ from: deployerAccount, gas: 3000000 });
    console.log('Rankings contract set in Profiles contract');

    // Set Contributions contract in Profiles contract
    await profilesContract.methods.setContributionsContract(contributionsContract.options.address).send({ from: deployerAccount, gas: 3000000 });
    console.log('Contributions contract set in Profiles contract');

    // Create a community
    const createCommunityResult = await profilesContract.methods.createCommunity(
      "Test Community",
      "A test community for governance",
      "https://example.com/community.jpg",
      "TestToken",
      "TST"
    ).send({ from: deployerAccount, gas: 5000000 });
    console.log('Community created:', createCommunityResult.events.CommunityCreated.returnValues);

    // Log initial community state
    console.log("Initial community state:");
    await logCommunityState(1);

    // Add users to the community
    for (let i = 0; i < userAccounts.length; i++) {
      await profilesContract.methods.createProfileAndJoinCommunity(
        `User${i + 1}`,
        `Description for User${i + 1}`,
        `https://example.com/user${i + 1}.jpg`,
        1 // communityId
      ).send({ from: userAccounts[i], gas: 3000000 });
      console.log(`User${i + 1} added to the community`);
    }

    // Get the current week
    let currentWeek = await contributionsContract.methods.getCurrentWeek(1).call();
    console.log('Current week:', currentWeek);

    // Log community profile
    const initialCommunityProfile = await profilesContract.methods.getCommunityProfile(1).call();
    console.log('Initial community profile:', initialCommunityProfile);

    // Submit contributions
    console.log('\nSubmitting contributions...');
    const allContributions = [];
    for (let i = 0; i < userAccounts.length; i++) {
      try {
        const contribution = [{
          name: `Contribution from User${i + 1}`,
          description: `Description of contribution from User${i + 1}`,
          links: [`https://example.com/contribution${i + 1}`]
        }];
        await contributionsContract.methods.submitContributions(1, contribution).send({ from: userAccounts[i], gas: 3000000 });
        console.log(`User${i + 1} submitted a contribution`);
        allContributions.push({ user: `User${i + 1}`, contribution: contribution[0] });
      } catch (error) {
        console.error(`Error submitting contribution for User${i + 1}:`, error.message);
      }
    }

    // Log all submitted contributions
    console.log('\nAll submitted contributions:');
    allContributions.forEach((item, index) => {
      console.log(`Contribution ${index + 1}:`);
      console.log(`  User: ${item.user}`);
      console.log(`  Name: ${item.contribution.name}`);
      console.log(`  Description: ${item.contribution.description}`);
      console.log(`  Links: ${item.contribution.links.join(', ')}`);
    });

    // Update current week
    currentWeek = await contributionsContract.methods.getCurrentWeek(1).call();
    console.log('\nUpdated current week:', currentWeek);

    // Log weekly contributors after submitting contributions
    const weeklyContributorsAfterSubmission = await contributionsContract.methods.getWeeklyContributors(1, currentWeek).call();
    console.log('\nWeekly contributors after submission:', weeklyContributorsAfterSubmission);

    // Log community state before changing
    console.log("\nCommunity state before changing to ContributionRanking:");
    await logCommunityState(1);

    // Check and adjust event count if necessary
    const communityProfileBeforeChange = await profilesContract.methods.getCommunityProfile(1).call();
    if (parseInt(communityProfileBeforeChange[6]) !== parseInt(currentWeek)) {
        console.log('Warning: Event count does not match current week. Adjusting...');
        // Assuming you've added an adjustEventCount function to your contract
        await profilesContract.methods.adjustEventCount(1, currentWeek).send({ from: deployerAccount, gas: 5000000 });
    }

    // Change state to ContributionRanking
    console.log('\nChanging state to ContributionRanking...');
    await profilesContract.methods.changeState(1).send({ from: deployerAccount, gas: 5000000 });
    console.log('Community state changed to ContributionRanking');

    // Log state after change
    console.log("\nCommunity state after changing to ContributionRanking:");
    await logCommunityState(1);

    // Get groups and submit rankings
    const groups = await contributionsContract.methods.getGroupsForWeek(1, currentWeek).call();
    console.log('Groups:', groups);

    if (groups.length > 0) {
      for (let groupId = 0; groupId < groups.length; groupId++) {
        const members = groups[groupId].members;
        for (const member of members) {
          const ranking = Array.from({ length: members.length }, (_, i) => i + 1);
          ranking.sort(() => Math.random() - 0.5); // Randomize ranking
          await rankingsContract.methods.submitRanking(1, currentWeek, groupId, ranking).send({ from: member, gas: 3000000 });
          console.log(`Ranking submitted by ${member} for group ${groupId}`);
        }
      }
    } else {
      console.log('No groups available for ranking submission');
    }

    // Change state back to ContributionSubmission
    console.log('\nChanging state back to ContributionSubmission...');
    await profilesContract.methods.changeState(1).send({ from: deployerAccount, gas: 8000000 });
    console.log('Community state changed back to ContributionSubmission');

    // Log final community state
    console.log("\nFinal community state:");
    await logCommunityState(1);

    // Verify results (only if groups are not empty)
    if (groups.length > 0) {
      for (let groupId = 0; groupId < groups.length; groupId++) {
        console.log(`\nResults for Group ${groupId}:`);
        const consensusRanking = await rankingsContract.methods.getConsensusRanking(1, currentWeek, groupId).call();
        console.log('Consensus Ranking:', consensusRanking.rankedScores);
        console.log('Transient Scores:', consensusRanking.transientScores);

        // Check respect distribution
        for (const member of groups[groupId].members) {
          const respectData = await contributionsContract.methods.getUserRespectData(member, 1).call();
          console.log(`Respect data for ${member}:`, {
            totalRespect: respectData.totalRespect / 1000, // Divide by SCALING_FACTOR
            averageRespect: respectData.averageRespect / 1000, // Divide by SCALING_FACTOR
            last12WeeksRespect: respectData.last12WeeksRespect.map(r => r / 1000) // Divide by SCALING_FACTOR
          });
        }
      }
    } else {
      console.log('No groups available for result verification');
    }

    // Verify ERC20 token creation
    const communityProfileAfter = await profilesContract.methods.getCommunityProfile(1).call();
    const tokenAddress = communityProfileAfter[7];
    console.log('\nERC20 Token Address:', tokenAddress);
    console.log('ERC20 token created:', tokenAddress !== '0x0000000000000000000000000000000000000000');

    // Log relevant events
    console.log('\nRelevant Events:');
    await logEvents(profilesContract, 'CommunityStateChanged');
    await logEvents(rankingsContract, 'ConsensusReached');
    await logEvents(rankingsContract, 'RespectIssued');
    await logEvents(rankingsContract, 'RespectIssueFailed');

    console.log('\nScript execution completed successfully.');
  } catch (error) {
    console.error('Error:', error.message);
    console.error('Error stack:', error.stack);
  }
})();