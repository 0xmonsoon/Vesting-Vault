//SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

/// @title A Vesting Vault to complete the challenge here: https://twitter.com/BowTiedPickle/status/1577320682395951109
/// @author 0xmonsoon (https://twitter.com/0xmonsoon)
/// @notice You can use this contract to lock ether and multiple erc20 tokens
/// @notice Multiple vesting schemes are available
/// @notice Amount can be locked only once

contract VestingVault is Ownable{

    using SafeERC20 for IERC20;

    bool public amountLocked;
    address payable public immutable beneficiary;
    uint public immutable maxDuration;
    uint public unlock;
    uint public start;
    uint public etherWithdrawn;
    mapping (address => uint) tokenWithdrawn;

    /// @dev _token address will be zero address in case of withdrawal of ether
    event Withdraw(address indexed _token, uint indexed _amount);

    /// @dev set beneficiary and maxDuration
    constructor (address payable _beneficiary, uint _maxDuration){
        require(_beneficiary != address(0), "zero address cannot be benificiary");
        beneficiary = _beneficiary;
        maxDuration = _maxDuration;
    }

    modifier notLocked(){
        require(!amountLocked, "Amount already vested");
        _;
        amountLocked = true;
    }
    

    /// @dev checks that the vesting period is less than the max vesting period saved in maxDuration

    modifier lessThanMaxDuration(uint _unlock, uint _cliff){
        require(block.timestamp > _unlock && _unlock - block.timestamp <= maxDuration && _cliff <= maxDuration, "vesting duration cannot be more than maxDuration");
        _;
    }

    modifier onlyBenefciary(){
        require(msg.sender == beneficiary, "Only beneficiary can call this function");
        _;
    }

    /// @notice implements the basic case where tokens and ether once locked can only be withdrawn after a fixed time.
    /// @param _unlock unix time in secs when amount will be unlocked

    function vestAndUnlockAllAtOnce(uint _unlock) payable external onlyOwner notLocked lessThanMaxDuration(_unlock, 0) {
        _vest(_unlock, _unlock);
    }

    /// @notice implements the  case where tokens and ether will be unlocked linearly without a cliff
    /// @param _unlock unix time in secs when amount will be unlocked

    function vestLinear(uint _unlock) payable external onlyOwner notLocked lessThanMaxDuration(_unlock, 0){
        _vest(_unlock, block.timestamp);
    }

    /// @dev implements the  case where tokens and ether will be unlocked linearly without a cliff
    /// @param _unlock unix time when amount will be unlocked
    /// @param _cliff seconds after which linear vesting will start

    function vestLinearWithCliff(uint _unlock, uint _cliff) payable external onlyOwner notLocked lessThanMaxDuration(_unlock, _cliff){
        _vest(_unlock, block.timestamp + _cliff);
    }

    /// @dev internal function which sets the state variables unlock and start according to various vesting schemes
    function _vest(uint _unlock, uint _start) internal{
        unlock = _unlock;
        start = _start;
    }

    /// @notice to check how many much of a particular erc20 is unlocked
    /// @param _token the address of the erc20 token
    /// @return amount of the erc20 token that has unlocked
    function tokenVested(address _token) public view returns (uint){

        if(block.timestamp < start){
            revert("Too Soon");
        }
        uint _balance = IERC20(_token).balanceOf(address(this));
        return ((block.timestamp - start) / (unlock - start)) * (_balance + tokenWithdrawn[_token]);
    }

    /// @notice to check how many much ether has unlocked
    /// @return amount of ether that has unlocked
    function etherVested() public view returns (uint){

        if(block.timestamp < start){
            revert("Too Soon");
        }
        uint _balance = address(this).balance;
        return ((block.timestamp - start) / (unlock - start)) * (_balance + etherWithdrawn);
    }

    /// @notice To withdraw unlocked ether by beneficiary
    function withdrawEther() public onlyBenefciary {
        uint amountVested = etherVested();
        require(amountVested > etherWithdrawn);
        uint withdrawAmount = amountVested-etherWithdrawn;
        etherWithdrawn = amountVested;

        emit Withdraw(address(0), withdrawAmount);
        (bool success, ) = beneficiary.call{value:withdrawAmount}("");
        require(success, "withdraw failed");
    }

    /// @notice To withdraw unlocked erc20 token by beneficiary
    function withdrawToken(address _token) public onlyBenefciary {
        uint amountVested = tokenVested(_token);
        require(amountVested > tokenWithdrawn[_token]);
        uint withdrawAmount = amountVested-tokenWithdrawn[_token];

        emit Withdraw(_token, withdrawAmount);
        tokenWithdrawn[_token] = amountVested;
        IERC20(_token).safeTransfer(beneficiary, withdrawAmount);
    }
}

