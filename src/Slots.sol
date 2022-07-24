// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract videoSlotsTest is VRFConsumerBaseV2 {

  // Events for both regular results and full jackpot win
  event Result(address indexed player, uint256[15] resultArray, uint256[20] jackpotResultArray, uint256 conJackpot);

  // Mask for bitshifting
  uint256 constant mask = ((0x1 << 8) - 1);

  // Fruity token address, jackpot dec, owner address dec.
  ERC20 public FRTST;
  uint256 jackpot;
  address owner;

  // Number of confirmations for VRF request, number of random numbers to request, limit for gas used to callback when VRF returns results.
  uint16 requestConfirmations = 3;
  uint32 numWords = 1;
  uint32 callbackGasLimit = 1000000;

  // LINK sub ID, VRF contract defs.
  uint64 s_subscriptionId;
  VRFCoordinatorV2Interface COORDINATOR;
  LinkTokenInterface LINKTOKEN;

  // Mappings; first var defined is a key, second is the value.
  mapping(uint256 => uint256) s_requestIdToRequestIndex;
  mapping(uint256 => address) public addressToRequestIndex;
  mapping(uint256 => uint256[]) public s_requestIndexToRandomWords;

  // Player Bet and Lines mapping tables
  mapping(address => uint256) public betToAddressIndex;
  mapping(address => uint256) public linesToAddressIndex;

  // For request ID count
  uint256 public requestCounter;

  /// VRF Co-ordinator, LINK token and gaslane keyhash setup for BSC Chain Testnet
  address vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
  address link = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;
  bytes32 keyHash = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

  constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    LINKTOKEN = LinkTokenInterface(link);
    s_subscriptionId = subscriptionId;
    FRTST = ERC20(0x36812bee855FbAA1a656BE4cc3eb82d209C40073);
    owner = msg.sender;
    jackpot = 25000;
  }

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  function withdraw(uint256 amount) external onlyOwner {
    FRTST.transfer(owner, (amount * (10 ** 18)));
  }

  function playerBet(uint256 bet, uint256 lines) external {
    require(bet <= 10, "Bet cannot be higher than 10 at this time"); require(bet > 0, "Bet cannot be zero");
    require(lines <= 20, "Cannot bet on more than 20 paylines"); require(lines > 0, "Cannot bet on zero paylines");
    require(FRTST.balanceOf(msg.sender) >= (bet*lines), "Error: Balance not high enough to make bet.");

    uint256 requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      numWords
    );

    //FRTST.transferFrom(msg.sender, address(this), ((bet * lines) * (10 ** 18)));
    betToAddressIndex[msg.sender] = bet;
    linesToAddressIndex[msg.sender] = lines;

    // Save unique request ID against the almighty request counter
    s_requestIdToRequestIndex[requestId] = requestCounter;
    // Save Address against requestCounter value
    addressToRequestIndex[requestCounter] = msg.sender;
    // Increment requestCounter ready for another request
    requestCounter += 1;
  }

  // Jackpot part of the payout function is now the problem
  function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
    uint256 requestNumber = s_requestIdToRequestIndex[requestId];
    address playerID = addressToRequestIndex[requestNumber];

    // Result arrays for use in contract and JS
    uint256[15] memory resArray;
    uint256[20] memory jackpotResults;

    // Now we split the number into 15 random numbers, 1 - 100. These are used for "weighting" the symbols, seen in the symCalc function. This gives us an array of 15 numbers from 1 - 7. 
    for (uint256 n=0; n < 15; n++){
      resArray[n] = symCalc(((randomWords[0] >> (n * 8)) & mask) % 101);
    }

    // Then we split the jackpot number into 20 random numbers from 1 - 32, weighting for this is done in the jackpot function in case of a jackpot win happening.
    for (uint256 n=0; n < 20; n++){
      jackpotResults[n] = (((randomWords[0] >> ((n * 8) & mask)) % 32) + 1);
    }
    
    // Add 1/3rd of the total bet to the jackpot amount, any total bet of 3 frty or more will add to the jackpot total.
    jackpot += ((betToAddressIndex[playerID] * linesToAddressIndex[playerID]) / 3);

    lineCheckAndPayout(betToAddressIndex[playerID], linesToAddressIndex[playerID], resArray /*jackpotResults*/);
  
    emit Result(playerID, resArray, jackpotResults, jackpot);
  }

  function symCalc(uint256 result) pure internal returns(uint256 returnResult) {
    if (result <= 33){returnResult = 1;}
    else if (result <= 55){returnResult = 2;}
    else if (result <= 68){returnResult = 3;}
    else if (result <= 81){returnResult = 4;}
    else if (result <= 89){returnResult = 5;}
    else if (result <= 97){returnResult = 6;}
    else if (result <= 100){returnResult = 7;}
  }

  function lineCheckAndPayout(uint256 betAmount, uint256 lines, uint256[15] memory playerResults /*uint256[20] memory jackRes*/) pure internal returns(uint256 payout){
    uint256 pr1; uint256 pr2; uint256 pr3; uint256 pr4; uint256 pr5;
    uint256 symMatch;
    for(uint256 c = 1; c < lines; c++){
      if(c == 1){pr1 = 2; pr2 = 5; pr3 = 8; pr4 = 11; pr5 = 14;}
      if(c == 2){pr1 = 1; pr2 = 4; pr3 = 7; pr4 = 10; pr5 = 13;}
      if(c == 3){pr1 = 3; pr2 = 6; pr3 = 9; pr4 = 12; pr5 = 15;}
      if(c == 4){pr1 = 1; pr2 = 5; pr3 = 9; pr4 = 11; pr5 = 13;}
      if(c == 5){pr1 = 3; pr2 = 5; pr3 = 7; pr4 = 11; pr5 = 15;}
      if(c == 6){pr1 = 1; pr2 = 4; pr3 = 8; pr4 = 12; pr5 = 15;}
      if(c == 7){pr1 = 3; pr2 = 6; pr3 = 8; pr4 = 10; pr5 = 13;}
      if(c == 8){pr1 = 2; pr2 = 4; pr3 = 8; pr4 = 12; pr5 = 14;}
      if(c == 9){pr1 = 2; pr2 = 6; pr3 = 8; pr4 = 10; pr5 = 14;}
      if(c == 10){pr1 = 1; pr2 = 5; pr3 = 8; pr4 = 11; pr5 = 15;}
      if(c == 11){pr1 = 3; pr2 = 5; pr3 = 8; pr4 = 11; pr5 = 13;}
      if(c == 12){pr1 = 2; pr2 = 4; pr3 = 7; pr4 = 11; pr5 = 15;}
      if(c == 13){pr1 = 2; pr2 = 6; pr3 = 9; pr4 = 11; pr5 = 13;}
      if(c == 14){pr1 = 2; pr2 = 5; pr3 = 7; pr4 = 11; pr5 = 15;}
      if(c == 15){pr1 = 2; pr2 = 5; pr3 = 9; pr4 = 11; pr5 = 13;}
      if(c == 16){pr1 = 1; pr2 = 4; pr3 = 8; pr4 = 12; pr5 = 14;}
      if(c == 17){pr1 = 3; pr2 = 6; pr3 = 8; pr4 = 10; pr5 = 14;}
      if(c == 18){pr1 = 2; pr2 = 4; pr3 = 8; pr4 = 12; pr5 = 15;}
      if(c == 19){pr1 = 2; pr2 = 6; pr3 = 8; pr4 = 10; pr5 = 13;}
      if(c == 20){pr1 = 1; pr2 = 4; pr3 = 7; pr4 = 11; pr5 = 15;}

      if((playerResults[pr1] == playerResults[pr2]) && (playerResults[pr2] == playerResults[pr3]) && (playerResults[pr3] == playerResults[pr4]) && (playerResults[pr4] == playerResults[pr5])){
        symMatch = 5;
      }
      else if((playerResults[pr1] == playerResults[pr2]) && (playerResults[pr2] == playerResults[pr3]) && (playerResults[pr3] == playerResults[pr4])){
        symMatch = 4;
      }
      else if((playerResults[pr1] == playerResults[pr2]) && (playerResults[pr2] == playerResults[pr3])){
        symMatch = 3;
      }
      else if(playerResults[pr1] == playerResults[pr2]){
        symMatch = 2; 
      }

      if(playerResults[pr1] == 1){
        payout += (symMatch * betAmount);
      }
      else if(playerResults[pr1] == 2){
        if(symMatch == 2){
          payout += (betAmount * 2);
        }
        else if(symMatch == 3){
          payout += (betAmount * 3);
        }
        else if(symMatch == 4){
          payout += (betAmount * 5);
        } 
        else if(symMatch == 5){
          payout += (betAmount * 10);
        }
      }
      else if((playerResults[pr1] == 3) || (playerResults[pr1] == 4)){
        if(symMatch == 2){
          payout += (betAmount * 3);
        }
        else if(symMatch == 3){
          payout += (betAmount * 10);
        }
        else if(symMatch == 4){
          payout += (betAmount * 15);
        }
        else if(symMatch == 5){
          payout += (betAmount * 20);
        }
      }
      else if((playerResults[pr1] == 5) || (playerResults[pr1] == 6)){
        if(symMatch == 2){
          payout += (betAmount * 5); 
        }
        else if(symMatch == 3){
          payout += (betAmount * 15); 
        }
        else if(symMatch == 4){
          payout += (betAmount * 20); 
        }
        else if(symMatch == 5){
          payout += (betAmount * 30); 
        }
      }
      else if(playerResults[pr1] == 7){
        if(symMatch == 2){
            payout += (betAmount * 10);
        }
        /*
        else if(symMatch == 3){
          if(jackRes[c] <= 16){
            payout += (betAmount * 25);
          }
          else if(jackRes[c] <= 22) {
            payout += (betAmount * 50);
          }
          else if(jackRes[c] <= 28) {
            payout += (betAmount * 100);
          }
          else if(jackRes[c] <= 32){
            payout += (betAmount * 200);
          }
        }
        else if (symMatch == 4){
          if(jackRes[c] <= 16){
            payout += (betAmount * 50);
          }
          else if(jackRes[c] <= 22) {
            payout += (betAmount * 100);
          }
          else if(jackRes[c] <= 28) {
            payout += (betAmount * 200);
          }
          else if(jackRes[c] <= 32){
            payout += (betAmount * 300);
          }
        }
        else if (symMatch == 5){
          if(jackRes[c] <= 16){
            payout += (betAmount * 100);
          }
          else if(jackRes[c] <= 22) {
            payout += (betAmount * 200);
          }
          else if(jackRes[c] <= 28) {
            payout += (betAmount * 250);
          }
          else if(jackRes[c] <= 32){
            payout += jackpotWin();
          }
        }
        */
      }
    }
  }
  function jackpotWin() internal returns(uint256 jw){
    jw = jackpot; jackpot = 25000;
  }
}