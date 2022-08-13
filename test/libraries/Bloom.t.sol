// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "src/libraries/Bloom.sol";

contract WinlineTest is Test {
    uint256 constant MAX_UINT256 = 2**256 - 1;
    mapping(uint256 => bool) usedWinlines;

    function setUp() public virtual {}

    function generateWinline(uint256 entropy) internal pure returns (uint256 out) {
        out |= ((entropy % 3) + 1 & 3);
        out = (out << 2) | ((((entropy >> 4) % 3) + 1) & 3);
        out = (out << 2) | ((((entropy >> 8) % 3) + 1) & 3);
        out = (out << 2) | ((((entropy >> 12) % 3) + 1) & 3);
        out = (out << 2) | ((((entropy >> 16) % 3) + 1) & 3);
    }

    function testBloomFilterSingleItemFuzz(bytes32 item) public {
        uint256 bloom = 0;

        bloom = Bloom.insert(bloom, item);
        assert(Bloom.contains(bloom, item));
    }

    function testBloomFilterInsertCheckedFuzz(bytes32 item) public {
        uint256 bloom = 0;

        bloom = Bloom.insertChecked(bloom, item);
        vm.expectRevert("Duplicate item detected");
        Bloom.insertChecked(bloom, item);
    }

    // Test the bloom filter with random 5x5(25) winlines
    function testBloomFilterWinlineFuzz(bytes32 entropy) public {
        uint256 bloom = 0;
        uint256 falsePositives = 0;
        uint256[] memory winlines = new uint256[](25);

        for (uint256 i = 0; i < 25; i++) {
            uint256 winline = generateWinline(uint256(keccak256(abi.encodePacked(entropy, i))));

            // If the winline has been previously generated and indexed with the mapping
            if (usedWinlines[winline] == true) {
                // Assert the bloom filter also contains that winline
                assert(Bloom.contains(bloom, bytes32(winline)));
            } else {
                if (Bloom.contains(bloom, bytes32(winline))) {
                    falsePositives += 1;
                }
                // Insert the winline and catalogue it as 'seen' via the mapping
                bloom = Bloom.insert(bloom, bytes32(winline));
                usedWinlines[winline] = true;
            }

            // Add to winlines, to be used for parity check later
            winlines[i] = winline;
        }

        // We want our failure rate to be around 1%~ max
        assert(falsePositives < 3);
        emit log_uint(falsePositives);

        // Ensure that all 25 winlines have been catalogued by the bloom filter
        for (uint256 j = 0; j < 25; j++) {
            assert(Bloom.contains(bloom, bytes32(winlines[j])));
            usedWinlines[winlines[j]] = false;
        }
    }

    function testBloomFilterSpecialSymbols() public {
        uint256 bloom = 0;

        for (uint256 i = 0; i <= 15; i++) {
            bloom = Bloom.insertChecked(bloom, bytes32(i));
        }
    }
}