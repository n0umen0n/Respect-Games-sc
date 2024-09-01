// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
/**
 * @title CommunityGovernance
 * @dev Manages community creation, membership, and contributions
 * @custom:dev-run-script /script/resptest.js
*/
contract LiquidRespectDistribution {
    // Fibonacci function
    function fib(uint8 n) internal pure returns (uint256) {
        if (n <= 1) return n;
        uint256 a = 0;
        uint256 b = 1;
        for (uint8 i = 2; i <= n; i++) {
            uint256 c = a + b;
            a = b;
            b = c;
        }
        return b;
    }

    // Function to distribute liquid respect
    function distributeRespect(uint256 totalRespect, uint256[][] memory groupRankings) public pure returns (uint256[] memory) {
        uint256 totalParticipants = 0;
        for (uint256 i = 0; i < groupRankings.length; i++) {
            totalParticipants += groupRankings[i].length;
        }
        
        uint256[] memory distribution = new uint256[](totalParticipants);
        uint256 totalWeight = 0;
        uint256 currentIndex = 0;

        // Calculate total weight and initial distribution
        for (uint256 i = 0; i < groupRankings.length; i++) {
            for (uint256 j = 0; j < groupRankings[i].length; j++) {
                uint256 weight = fib(uint8(6 - j)); // 6 is used as the starting point, adjust if needed
                totalWeight += weight;
                distribution[currentIndex] = weight;
                currentIndex++;
            }
        }

        // Normalize distribution
        for (uint256 i = 0; i < distribution.length; i++) {
            distribution[i] = (distribution[i] * totalRespect) / totalWeight;
        }

        return distribution;
    }

    // Helper function to get the sum of distributed respect
    function getSumOfDistribution(uint256[] memory distribution) public pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < distribution.length; i++) {
            sum += distribution[i];
        }
        return sum;
    }
}