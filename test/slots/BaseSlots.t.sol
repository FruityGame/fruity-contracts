// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "test/mocks/slots/MockBaseSlots.sol";

import "src/libraries/Board.sol";

contract BaseSlotsTest is Test {
    // 01|01|01|01|01
    uint256 constant WINLINE = 341;
    // 01|10|11|10|01
    uint256 constant WINLINE_WINNER = 441;
    // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0000|0001]
    uint256 constant BOARD = 281479288520705;
    uint256 constant WINNING_ENTROPY = uint256(keccak256(abi.encodePacked(uint256(255))));

    uint32 constant WILDCARD = 4;
    uint32 constant SCATTER = 5;
    
    event BetPlaced(address indexed user, uint256 betId);
    event BetFulfilled(address indexed user, uint256 board, uint256 payoutWad);

    MockBaseSlots slots;

    function setUp() public virtual {
        slots = new MockBaseSlots(
            SlotParams(3, 5, 6, WILDCARD, SCATTER, 255, 115, 20, 5, 500, 1e18)
        );
    }

    function bytesToEntropy(bytes32 b) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(b)));
    }

    function entropyToSymbol(uint256 entropy, SlotParams memory params) internal pure returns (uint256) {
        return entropy % params.symbols;
    }

    function entropyToCount(uint256 entropy, SlotParams memory params) internal pure returns (uint256) {
        return entropy % params.reels;
    }

    // Not good code but its for a test, it fits its purpose
    function generateScatterBoard(uint256 entropy) internal view returns (uint256 scatterCount, uint256 out) {
        SlotParams memory params = slots.getParams();
        uint256 boardSize = params.rows * params.reels;

        if (boardSize == 0) return (0, 0);

        uint256 symbol = entropyToSymbol(entropy, params);
        if (symbol == SCATTER) scatterCount++;
        out |= symbol;

        for (uint256 i = 1; i < boardSize; i++) {
            symbol = entropyToSymbol((entropy >> 2*i) + i, params);
            if (symbol == SCATTER) scatterCount++;
            out = (out << 4) | symbol;
        }
    }

    function testCheckScatterFuzz(bytes32 b) public {
        uint256 randomness = bytesToEntropy(b);
        (uint256 count, uint256 board) = generateScatterBoard(randomness);

        assertEq(slots.checkScatterExternal(board), count);
    }

    function testCheckScatterMinMax() public {
        assertEq(slots.checkScatterExternal(BOARD), 0);

        // 2:[0000|0000|0001|0000|0000] 1:[0000|0001|0000|0001|0000] 0:[0001|0000|0000|0101|0001]
        uint256 boardWithScatter = 281479288520785;
        assertEq(slots.checkScatterExternal(boardWithScatter), 1);

        // 2:[0101|0101|0101|0101|0101] 1:[0101|0101|0101|0101|0101] 0:[0101|0101|0101|0101|0101]
        uint256 boardFullScatter = 384307168202282325;
        assertEq(slots.checkScatterExternal(boardFullScatter), 15);
    }

    function testResolveSymbolFuzz(bytes32 b) public {
        SlotParams memory params = slots.getParams();
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);

        uint256 entropy = bytesToEntropy(b);
        uint256 symbol = entropyToSymbol(entropy, params);
        uint256 count = entropyToCount(entropy >> 16, params);

        if (symbol == SCATTER) {
            vm.expectRevert("Symbol cannot be a scatter symbol");
            slots.resolveSymbolExternal(symbol, count, entropy, session, params);
            return;
        }

        uint256 payout = slots.resolveSymbolExternal(symbol, count, entropy, session, params);

        if (count > 2) {
            // God damn awful default formula that needs to be broken down
            uint256 expected = session.betWad * (((symbol + 1) * MAX_SYMBOL) / (params.symbols + 1)) * (count - (params.reels / 2));
            assertEq(payout, expected);
        }
    }

    function testResolveSymbolInvalidSymbol() public {
        SlotParams memory params = slots.getParams();
        vm.expectRevert("Invalid symbol parsed from board for this contract");
        slots.resolveSymbolExternal(params.symbols + 1, 0, 0, SlotSession(address(this), 0, 0, 0), params);
    }

    function testResolveSymbolScatter() public {
        SlotParams memory params = slots.getParams();
        vm.expectRevert("Symbol cannot be a scatter symbol");
        slots.resolveSymbolExternal(params.scatterSymbol, 0, 0, SlotSession(address(this), 0, 0, 0), params);
    }

    function testResolveSymbolJackpot() public {
        SlotParams memory params = slots.getParams();
        uint256 count = 3;

        // Test rolling 3 'jackpot' symbols with a successful jackpot roll after
        slots.setJackpot(1e18);
        uint256 payout = slots.resolveSymbolExternal(
            params.symbols,
            count,
            2**256 - 1,
            SlotSession(address(this), 1e18, 0, 0),
            params
        );

        uint256 expectedBasePayout = 1e18 *(
            ((params.symbols + 1) * MAX_SYMBOL) /
            (params.symbols + 1)) * (count - (params.reels / 2)
        );

        // Ensure we were credited the expected payout + the jackpot
        assertEq(payout, expectedBasePayout + 1e18);
        assertEq(slots.jackpotWad(), 0);

        // Test rolling 3 'jackpot' symbols, but failing the jackpot roll after
        slots.setJackpot(1e18);
        uint256 payoutWithoutJackpot = slots.resolveSymbolExternal(
            params.symbols,
            count,
            0,
            SlotSession(address(this), 1e18, 0, 0),
            params
        );

        // Ensure jackpot has not been paid out, failed jackpot roll
        assertEq(payoutWithoutJackpot, expectedBasePayout);
        assertEq(slots.jackpotWad(), 1e18);
    }

    function testAvailableAssets() public {
        // Set jackpot to be larger than balance
        slots.setBalance(1e18);
        slots.setJackpot(2e18);

        // Ensure no overflows and our available balance is 0
        assertEq(slots.availableAssets(), 0);

        // Set jackpot to be equal to our balance
        slots.setJackpot(1e18);

        assertEq(slots.availableAssets(), 0);

        // Set jackpot to be half of our available balance
        slots.setJackpot(0.5e18);

        // Ensure no overflows and our available balance is halved
        assertEq(slots.availableAssets(), 0.5e18);

        // Set jackpot to be zero
        slots.setJackpot(0);

        // Ensure we have the full balance available
        assertEq(slots.availableAssets(), 1e18);
    }
    
    function testBeginBet() public {
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);

        // Should emit an event to notify the front end
        vm.expectEmit(true, false, false, true);
        emit BetPlaced(address(this), uint256(1));
        slots.beginBetExternal(session);

        assertEq(slots.balance(), 1e18);
    }

    // Mock is setup with locks that verify the session is ended before the payout begins
    // If the refund logic is called before endSession, the test should fail
    function testCancelBet() public {
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);

        slots.beginBetExternal(session);
        slots.cancelBet(1);

        assertEq(slots.balance(), 0);
    }

    function testCancelBetInvalidUser() public {
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);
        slots.beginBetExternal(session);

        // Attempt to cancel our bet from a different account
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSlots.InvalidSession.selector,
                address(0xDEADBEEF),
                uint256(1)
            )
        );
        vm.prank(address(0xDEADBEEF));
        slots.cancelBet(1);

        // Ensure our bet is still in the slots
        assertEq(slots.balance(), 1e18);

        // Cancel our bet
        slots.cancelBet(1);
        assertEq(slots.balance(), 0);
    }

    function testFulfillBet() public {
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);
        slots.beginBetExternal(session);
        
        // Setup Board to return a mock board
        vm.mockCall(
            address(slots),
            abi.encodeWithSignature("(uint256,struct SlotParams memory) pure returns (uint256)"),
            abi.encode(uint256(0))
        );
        // Setup the mock to return 0.5 Eth as the 'result' from the parsed board
        slots.setProcessSessionResult(0.5e18);

        // Expect an event to be emitted to relay information back to the frontend
        vm.expectEmit(true, false, false, true);
        emit BetFulfilled(address(this), uint256(0), uint256(0.5e18));
        slots.fulfillRandomnessExternal(1, 0);

        // Ensure we've been paid out 0.5 Eth
        assertEq(slots.balance(), 0.5e18);
        // Ensure the jackpot has been incremented
        assertEq(slots.jackpotWad(), uint256(1e18) / 3);
    }

    function testFulfillBetNoScatter() public {
        // The mock is setup to throw an exception if the scatter symbol resolves.
        // If the scatter symbol is set to a value larger than the number of symbols
        // this contract can process, it is assumed that the machine is configured with no
        // scatter symbol functionality
        MockBaseSlots slotsNoScatter = new MockBaseSlots(
            SlotParams(3, 5, 6, WILDCARD, 7, 255, 115, 20, 5, 500, 1e18)
        );

        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);
        slotsNoScatter.beginBetExternal(session);
        slotsNoScatter.setProcessSessionResult(0.5e18);
        slotsNoScatter.fulfillRandomnessExternal(1, 0);

        // Ensure we've been paid out 0.5 Eth
        assertEq(slotsNoScatter.balance(), 0.5e18);
        // Ensure the jackpot has been incremented
        assertEq(slotsNoScatter.jackpotWad(), uint256(1e18) / 3);
    }

    function testFulfillBetReservedJackpot() public {
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);
        slots.beginBetExternal(session);

        // Setup a win of 1 Eth
        slots.setProcessSessionResult(1e18);
        // Setup a jackpot of 0.5 Eth
        slots.setJackpot(0.5e18);

        slots.fulfillRandomnessExternal(1, 0);
        // Ensure our payout is only 0.5 Eth (as we're reserving the jackpot)
        // Ensure we've been paid out 0.5 Eth - the jackpot
        uint256 expectedJackpot = uint256(1e18) / 3;
        assertEq(slots.balance(), 0.5e18 + expectedJackpot);
        // Ensure the jackpot has been incremented
        assertEq(slots.jackpotWad(), 0.5e18 + expectedJackpot);
    }

    function testFulfillBetZeroWinPayout() public {
        SlotSession memory session = SlotSession(address(this), 1e18, 0, 0);
        slots.beginBetExternal(session);
        
        // Setup the mock to return 0.5 Eth as the 'result' from the parsed board
        slots.setProcessSessionResult(0);

        // Expect an event to be emitted to relay information back to the frontend
        vm.expectEmit(true, false, false, true);
        emit BetFulfilled(address(this), uint256(0), uint256(0));
        slots.fulfillRandomnessExternal(1, 0);

        // Ensure we've paid out nothing
        assertEq(slots.balance(), 1e18);
        // Ensure the jackpot has been incremented
        assertEq(slots.jackpotWad(), uint256(1e18) / 3);
    }
}