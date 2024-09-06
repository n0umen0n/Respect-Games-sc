// SPDX-License-Identifier: MIT
(async () => {
  try {
    console.log('Starting Community Governance test script...');

    const accounts = await web3.eth.getAccounts();
    console.log('Accounts loaded:', accounts.length, 'accounts available');

    const deployerAccount = accounts[0];
    const userAccounts = accounts.slice(1, 14); // Use 13 user accounts

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

    // Helper function to verify respect distribution
    async function verifyRespectDistribution(communityId, initialAmount) {
      let totalDistributed = web3.utils.toBN(0);
      const members = await profilesContract.methods.getCommunityMembers(communityId).call();
      
      for (const member of members[0]) {
        const claimableTokens = await rankingsContract.methods.getClaimableTokens(communityId, member).call();
        totalDistributed = totalDistributed.add(web3.utils.toBN(claimableTokens.amount));
      }

      console.log('\nRespect Distribution Verification:');
      console.log('Initial amount to distribute:', web3.utils.fromWei(initialAmount, 'ether'));
      console.log('Total amount distributed:', web3.utils.fromWei(totalDistributed, 'ether'));
      
      const difference = web3.utils.toBN(initialAmount).sub(totalDistributed);
      console.log('Difference:', web3.utils.fromWei(difference, 'ether'));
      
      if (difference.isZero()) {
        console.log('Respect distribution is correct!');
      } else {
        console.log('Warning: Respect distribution does not match the initial amount');
      }
    }

    // Deploy MultiProxyAdmin
    console.log('Deploying MultiProxyAdmin...');
    const multiProxyAdminMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/MultiProxyAdmin.json'));
    let multiProxyAdmin = new web3.eth.Contract(multiProxyAdminMetadata.abi);
    multiProxyAdmin = await multiProxyAdmin.deploy({
      data: multiProxyAdminMetadata.data.bytecode.object,
      arguments: [deployerAccount]
    }).send({ from: deployerAccount, gas: 3000000 });
    console.log('MultiProxyAdmin deployed at:', multiProxyAdmin.options.address);

    // Deploy CommunityGovernanceProfiles implementation
    console.log('Deploying CommunityGovernanceProfiles implementation...');
    const profilesMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/CommunityGovernanceProfilesImplementation.json'));
    let profilesImplementation = new web3.eth.Contract(profilesMetadata.abi);
    profilesImplementation = await profilesImplementation.deploy({
      data: profilesMetadata.data.bytecode.object,
      arguments: []
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceProfiles implementation deployed at:', profilesImplementation.options.address);

    // Deploy CommunityGovernanceProfiles proxy
    console.log('Deploying CommunityGovernanceProfiles proxy...');
    const profilesProxyMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/ProfilesProxy.json'));
    const profilesInitData = profilesImplementation.methods.initialize(deployerAccount).encodeABI();
    let profilesProxy = new web3.eth.Contract(profilesProxyMetadata.abi);
    profilesProxy = await profilesProxy.deploy({
      data: profilesProxyMetadata.data.bytecode.object,
      arguments: [profilesImplementation.options.address, multiProxyAdmin.options.address, profilesInitData]
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceProfiles proxy deployed at:', profilesProxy.options.address);

    // Create contract instance for interacting with the proxy
    const profilesContract = new web3.eth.Contract(profilesMetadata.abi, profilesProxy.options.address);

    // Deploy CommunityGovernanceContributions implementation and proxy
    console.log('Deploying CommunityGovernanceContributions implementation...');
    const contributionsMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/CommunityGovernanceContributions.json'));
    let contributionsImplementation = new web3.eth.Contract(contributionsMetadata.abi);
    contributionsImplementation = await contributionsImplementation.deploy({
      data: contributionsMetadata.data.bytecode.object,
      arguments: []
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceContributions implementation deployed at:', contributionsImplementation.options.address);

    console.log('Deploying CommunityGovernanceContributions proxy...');
    const contributionsProxyMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/ContributionsProxy.json'));
    const contributionsInitData = contributionsImplementation.methods.initialize(deployerAccount).encodeABI();
    let contributionsProxy = new web3.eth.Contract(contributionsProxyMetadata.abi);
    contributionsProxy = await contributionsProxy.deploy({
      data: contributionsProxyMetadata.data.bytecode.object,
      arguments: [contributionsImplementation.options.address, multiProxyAdmin.options.address, contributionsInitData]
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceContributions proxy deployed at:', contributionsProxy.options.address);

    // Create contract instance for interacting with the proxy
    const contributionsContract = new web3.eth.Contract(contributionsMetadata.abi, contributionsProxy.options.address);

    // Deploy CommunityGovernanceRankings implementation and proxy
    console.log('Deploying CommunityGovernanceRankings implementation...');
    const rankingsMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/CommunityGovernanceRankings.json'));
    let rankingsImplementation = new web3.eth.Contract(rankingsMetadata.abi);
    rankingsImplementation = await rankingsImplementation.deploy({
      data: rankingsMetadata.data.bytecode.object,
      arguments: []
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceRankings implementation deployed at:', rankingsImplementation.options.address);

    console.log('Deploying CommunityGovernanceRankings proxy...');
    const rankingsProxyMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/RankingsProxy.json'));
    const rankingsInitData = rankingsImplementation.methods.initialize(deployerAccount).encodeABI();
    let rankingsProxy = new web3.eth.Contract(rankingsProxyMetadata.abi);
    rankingsProxy = await rankingsProxy.deploy({
      data: rankingsProxyMetadata.data.bytecode.object,
      arguments: [rankingsImplementation.options.address, multiProxyAdmin.options.address, rankingsInitData]
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('CommunityGovernanceRankings proxy deployed at:', rankingsProxy.options.address);

    // Create contract instance for interacting with the proxy
    const rankingsContract = new web3.eth.Contract(rankingsMetadata.abi, rankingsProxy.options.address);

    // Deploy MultiSig implementation and proxy
    console.log('Deploying MultiSig implementation...');
    const multiSigMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/CommunityGovernanceMultiSigImplementation.json'));
    let multiSigImplementation = new web3.eth.Contract(multiSigMetadata.abi);
    multiSigImplementation = await multiSigImplementation.deploy({
      data: multiSigMetadata.data.bytecode.object,
      arguments: []
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('MultiSig implementation deployed at:', multiSigImplementation.options.address);

    console.log('Deploying MultiSig proxy...');
    const multiSigProxyMetadata = JSON.parse(await remix.call('fileManager', 'getFile', 'contractsproxy/artifacts/MultiSigProxy.json'));
    const multiSigInitData = multiSigImplementation.methods.initialize(deployerAccount).encodeABI();
    let multiSigProxy = new web3.eth.Contract(multiSigProxyMetadata.abi);
    multiSigProxy = await multiSigProxy.deploy({
      data: multiSigProxyMetadata.data.bytecode.object,
      arguments: [multiSigImplementation.options.address, multiProxyAdmin.options.address, multiSigInitData]
    }).send({ from: deployerAccount, gas: 8000000 });
    console.log('MultiSig proxy deployed at:', multiSigProxy.options.address);

    // Create contract instance for interacting with the proxy
    const multiSigContract = new web3.eth.Contract(multiSigMetadata.abi, multiSigProxy.options.address);

    // Set contract addresses
    await profilesContract.methods.setRankingsContract(rankingsProxy.options.address).send({ from: deployerAccount, gas: 3000000 });
    await profilesContract.methods.setContributionsContract(contributionsProxy.options.address).send({ from: deployerAccount, gas: 3000000 });
    await profilesContract.methods.setMultiSigContract(multiSigProxy.options.address).send({ from: deployerAccount, gas: 3000000 });

    await contributionsContract.methods.setProfilesContract(profilesProxy.options.address).send({ from: deployerAccount, gas: 3000000 });

    // Updated setContracts call for rankings contract
    await rankingsContract.methods.setContracts(
      contributionsProxy.options.address,
      profilesProxy.options.address,
      multiSigProxy.options.address
    ).send({ from: deployerAccount, gas: 3000000 });

    // Set contract addresses for MultiSig
    console.log('Setting contract addresses for MultiSig...');
    try {
        await multiSigContract.methods.setProfilesContract(profilesProxy.options.address).send({ from: deployerAccount, gas: 3000000 });
        console.log('Profiles contract set in MultiSig contract');

        await multiSigContract.methods.setContributionsContract(contributionsProxy.options.address).send({ from: deployerAccount, gas: 3000000 });
        console.log('Contributions contract set in MultiSig contract');

        console.log('MultiSig contract addresses set successfully');
    } catch (error) {
        console.error('Error setting MultiSig contract addresses:', error.message);
        throw error;
    }
    console.log('Contract addresses set');

    // Create a community
    const createCommunityResult = await profilesContract.methods.createCommunity(
      "Test Community",
      "A test community for governance",
      "https://example.com/community.jpg",
      "TestToken",
      "TST"
    ).send({ from: deployerAccount, gas: 5000000 });
    console.log('Community created:', createCommunityResult.events.CommunityCreated.returnValues);

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

    // Function to run a week's cycle
    async function runWeekCycle(weekNumber) {
      console.log(`\n--- Starting Week ${weekNumber} ---`);

      // Get the current week
      let currentWeek = await contributionsContract.methods.getCurrentWeek(1).call();
      console.log(`Current week: ${currentWeek}`);

      // Submit contributions
      console.log('\nSubmitting contributions...');
      const allContributions = [];
      for (let i = 0; i < userAccounts.length; i++) {
        try {
          const contribution = [{
            name: `Contribution from User${i + 1} - Week ${weekNumber}`,
            description: `Description of contribution from User${i + 1} for Week ${weekNumber}`,
            links: [`https://example.com/contribution${i + 1}-week${weekNumber}`]
          }];
          await contributionsContract.methods.submitContributions(1, contribution).send({ from: userAccounts[i], gas: 3000000 });
          console.log(`User${i + 1} submitted a contribution for Week ${weekNumber}`);
          allContributions.push({ user: `User${i + 1}`, contribution: contribution[0] });
        } catch (error) {
          console.error(`Error submitting contribution for User${i + 1} in Week ${weekNumber}:`, error.message);
        }
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
            console.log(`Ranking submitted by ${member} for group ${groupId} in Week ${weekNumber}`);
          }
        }
      } else {
        console.log(`No groups available for ranking submission in Week ${weekNumber}`);
      }

      // Change state back to ContributionSubmission
      console.log('\nChanging state back to ContributionSubmission...');
      await profilesContract.methods.changeState(1).send({ from: deployerAccount, gas: 8000000 });
      console.log('Community state changed back to ContributionSubmission');

      // Log final community state
      console.log("\nFinal community state for Week ${weekNumber}:");
      await logCommunityState(1);

      // Verify results and check claimable tokens
      if (groups.length > 0) {
        for (let groupId = 0; groupId < groups.length; groupId++) {
          console.log(`\nResults for Group ${groupId} in Week ${weekNumber}:`);
          const consensusRanking = await rankingsContract.methods.getConsensusRanking(1, currentWeek, groupId).call();
          console.log('Consensus Ranking:', consensusRanking.rankedScores);
          console.log('Transient Scores:', consensusRanking.transientScores);

          // Check respect distribution and claimable tokens
          for (const member of groups[groupId].members) {
            const respectData = await contributionsContract.methods.getUserRespectData(member, 1).call();
            console.log(`Respect data for ${member} in Week ${weekNumber}:`, {
              totalRespect: respectData.totalRespect / 1000, // Divide by SCALING_FACTOR
              averageRespect: respectData.averageRespect / 1000, // Divide by SCALING_FACTOR
              last12WeeksRespect: respectData.last12WeeksRespect.map(r => r / 1000) // Divide by SCALING_FACTOR
            });

            const claimableTokens = await rankingsContract.methods.getClaimableTokens(1, member).call();
            console.log(`Claimable tokens for ${member} in Week ${weekNumber}:`, {
              amount: web3.utils.fromWei(claimableTokens.amount, 'ether'),
              claimed: claimableTokens.claimed
            });
          }
        }
      } else {
        console.log(`No groups available for result verification in Week ${weekNumber}`);
      }

      console.log(`--- End of Week ${weekNumber} ---\n`);
    }

    // Run two weeks of cycles
    await runWeekCycle(1);
    await runWeekCycle(2);

    // Verify ERC20 token creation
    const communityProfileAfter = await profilesContract.methods.getCommunityProfile(1).call();
    const tokenAddress = communityProfileAfter[7];
    console.log('\nERC20 Token Address:', tokenAddress);
    console.log('ERC20 token created:', tokenAddress !== '0x0000000000000000000000000000000000000000');

    // Create proposal to set respect amount
    console.log('\nCreating proposal to set respect amount...');
    const respectToDistribute = web3.utils.toWei('1000', 'ether'); // 1000 tokens
    const proposalId = 1;
    const proposalType = 1; // Assuming 1 corresponds to ProposalType.SetRespectToDistribute

    await multiSigContract.methods.createProposal(
      1, // communityId
      proposalId,
      proposalType,
      respectToDistribute,
      "0x0000000000000000000000000000000000000000" // null address for non-member-specific proposals
    ).send({ from: deployerAccount, gas: 3000000 });
    console.log('Respect to distribute proposal created');

    // Get and log the created proposal
    const proposal = await multiSigContract.methods.getProposal(1, proposalId).call();
    console.log('Created proposal:', proposal);

    // Sign the proposal (simulating other top respected users signing)
    console.log('\nSigning the proposal...');
    const topUsers = await multiSigContract.methods.getTopRespectedUsers(1).call();
    for (let i = 1; i < 3 && i < topUsers.length; i++) {
      if (topUsers[i] !== "0x0000000000000000000000000000000000000000") {
        await multiSigContract.methods.signProposal(1, proposalId).send({ from: topUsers[i], gas: 3000000 });
        console.log(`Proposal signed by ${topUsers[i]}`);
      }
    }

    // Check if the proposal was executed
    const updatedProposal = await multiSigContract.methods.getProposal(1, proposalId).call();
    console.log('\nUpdated proposal status:', updatedProposal);

    if (updatedProposal.executed) {
      console.log('Proposal was successfully executed');
    } else {
      console.log('Proposal was not executed. It might need more signatures or there might be an issue.');
    }

    // Verify respect distribution
    await verifyRespectDistribution(1, respectToDistribute);

    // Log relevant events
    console.log('\nRelevant Events:');
    await logEvents(profilesContract, 'CommunityStateChanged');
    await logEvents(rankingsContract, 'ConsensusReached');
    await logEvents(rankingsContract, 'RespectIssued');
    await logEvents(rankingsContract, 'TokensClaimed');
    await logEvents(multiSigContract, 'ProposalCreated');
    await logEvents(multiSigContract, 'ProposalExecuted');
    await logEvents(multiSigContract, 'MemberRemoved');

    console.log('\nScript execution completed successfully.');
  } catch (error) {
    console.error('Error:', error.message);
    console.error('Error stack:', error.stack);
  }
})();