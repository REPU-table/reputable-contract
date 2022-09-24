// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRepuERC20.sol";
import "./interfaces/IRepuFactory.sol";

contract RepuERC20 is
    IRepuERC20,
    ERC20Capped,
    ERC20Burnable,
    ERC20VotesComp,
    Ownable
{
    using SafeERC20 for IERC20;

    IRepuFactory public factory;
    IERC20 public repu;

    uint256 private constant ACC_TOKEN_PRECISION = 1e12;

    constructor(string memory symbol, address repu_)
        ERC20Capped(1000000000 * 10e18)
        ERC20(symbol, string(abi.encodePacked("r", symbol)))
        ERC20Permit(string(abi.encodePacked("r", symbol)))
    {
        factory = IRepuFactory(msg.sender);
        repu = IERC20(repu_);
    }

    //==================== MasterChef ====================//

    //
    mapping(address => UserInfo) public userInfo;

    uint256 internal _lastRewardBlock;
    uint256 internal _accTokenPerShare;

    // View function to see pending tokens on frontend.
    function pendingToken(address user_) public view returns (uint256 pending) {
        UserInfo storage user = userInfo[user_];
        uint256 accTokenPerShare = _accTokenPerShare;
        uint256 totalDeposited = repu.balanceOf(address(this));
        if (block.number > _lastRewardBlock && totalDeposited != 0) {
            uint256 blocks = block.number - _lastRewardBlock;
            uint256 tokenReward = blocks * factory.TOKEN_PER_BLOCK();
            accTokenPerShare +=
                (tokenReward * ACC_TOKEN_PRECISION) /
                totalDeposited;
        }
        pending = uint256(
            int256((user.amount * accTokenPerShare) / ACC_TOKEN_PRECISION) -
                user.rewardDebt
        );
    }

    // Update reward variables to be up-to-date.
    function update() public {
        if (block.number > _lastRewardBlock) {
            uint256 totalDeposited = repu.balanceOf(address(this));
            if (totalDeposited > 0) {
                uint256 blocks = block.number - _lastRewardBlock;
                uint256 tokenReward = blocks * factory.TOKEN_PER_BLOCK();
                _accTokenPerShare +=
                    (tokenReward * ACC_TOKEN_PRECISION) /
                    totalDeposited;

                _mint(address(this), tokenReward);
            }
            _lastRewardBlock = block.number;

            emit Update(_lastRewardBlock, totalDeposited, _accTokenPerShare);
        }
    }

    // TODO: rewarder
    // Deposit REPU tokens to RepuERC20 for RepuERC20 allocation.
    function deposit(uint256 amount_, address to_) public {
        update();

        address msgSender = _msgSender();
        UserInfo storage user = userInfo[msgSender];

        user.amount += amount_;
        user.rewardDebt += int256(
            (amount_ * _accTokenPerShare) / ACC_TOKEN_PRECISION
        );

        repu.safeTransferFrom(msgSender, address(this), amount_);

        emit Deposit(msgSender, amount_, to_);
    }

    // TODO: rewarder
    // Withdraw REPU tokens from RepuERC20.
    function withdraw(uint256 amount_, address to_) public {
        address msgSender = _msgSender();
        UserInfo storage user = userInfo[msgSender];

        update();

        user.rewardDebt -= int256(
            (amount_ * _accTokenPerShare) / ACC_TOKEN_PRECISION
        );
        user.amount -= amount_;

        repu.safeTransfer(to_, amount_);

        emit Withdraw(msgSender, amount_, to_);
    }

    // TODO: rewarder
    // Harvest proceeds for transaction sender to `to`.
    function harvest(address to_) public {
        update();

        address msgSender = _msgSender();
        UserInfo storage user = userInfo[msgSender];

        int256 accumulatedToken = int256(
            (user.amount * _accTokenPerShare) / ACC_TOKEN_PRECISION
        );
        uint256 _pendingToken = uint256(accumulatedToken - user.rewardDebt);

        user.rewardDebt = accumulatedToken;

        if (_pendingToken != 0) {
            _safeTokenTransfer(to_, _pendingToken);
        }

        emit Harvest(msgSender, _pendingToken, to_);
    }

    // TODO: rewarder
    // Withdraw tokens from this contract
    // and harvest proceeds for transaction sender to `to`.
    function withdrawAndHarvest(uint256 amount_, address to_) public {
        update();

        address msgSender = _msgSender();
        UserInfo storage user = userInfo[msgSender];

        int256 accumulatedToken = int256(
            (user.amount * _accTokenPerShare) / ACC_TOKEN_PRECISION
        );
        uint256 _pendingToken = uint256(accumulatedToken - user.rewardDebt);

        user.rewardDebt =
            accumulatedToken -
            int256((amount_ * _accTokenPerShare) / ACC_TOKEN_PRECISION);
        user.amount -= amount_;

        if (_pendingToken != 0) {
            _safeTokenTransfer(to_, _pendingToken);
        }

        repu.safeTransfer(to_, amount_);

        emit Withdraw(msgSender, amount_, to_);
        emit Harvest(msgSender, _pendingToken, to_);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address to_) public {
        address msgSender = _msgSender();
        UserInfo storage user = userInfo[msgSender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        repu.safeTransfer(to_, amount);
        emit EmergencyWithdraw(msgSender, amount, to_);
    }

    // Safe token transfer function,
    // just in case if rounding error causes this contract to not have enough Tokens.
    function _safeTokenTransfer(address to_, uint256 amount_) internal {
        uint256 tokenBal = balanceOf(address(this));
        if (amount_ > tokenBal) {
            transfer(to_, tokenBal);
        } else {
            transfer(to_, amount_);
        }
    }

    //==================== Inherited Functions ====================//

    /**
     * @dev Snapshots the totalSupply after it has been increased.
     *
     * See {ERC20-_mint}.
     */
    function _mint(address account, uint256 amount)
        internal
        virtual
        override(ERC20, ERC20Capped, ERC20Votes)
    {
        require(
            ERC20.totalSupply() + amount <= cap(),
            "ERC20Capped: cap exceeded"
        );
        ERC20Votes._mint(account, amount);
    }

    /**
     * @dev Snapshots the totalSupply after it has been decreased.
     * Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function _burn(address account, uint256 amount)
        internal
        virtual
        override(ERC20, ERC20Votes)
    {
        ERC20Votes._burn(account, amount);
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {DelegateVotesChanged} event.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Votes) {
        ERC20Votes._afterTokenTransfer(from, to, amount);
    }
}
