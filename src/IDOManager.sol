// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./EmergencyWithdrawAdmin.sol";
import "./kyc/WithKYCRegistry.sol";
import "./admin_manager/WithAdminManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IIDOManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract IDOManager is IIDOManager, ReentrancyGuard, Ownable, EmergencyWithdrawAdmin, WithKYCRegistry, WithAdminManager {
    using Math for uint256;

    uint256 public idoCount;

    mapping(uint256 => IDO) public idos;
    mapping(uint256 idoId => IDOSchedules) public idoSchedules;
    mapping(uint256 idoId => IDORefundInfo) public idoRefundInfo;
    mapping(uint256 idoId => IDOPricing) public idoPricing;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    address public immutable usdt;
    address public immutable usdc;
    address public immutable flx;

    uint256 private constant DECIMALS = 1e18;
    uint32 private constant HUNDRED_PERCENT = 10_000_000;
    uint256 private constant PRICE_DECIMALS = 1e8;

    uint8 private constant PHASE_DIVIDER = 3;
    uint16 private constant FLX_PRIORITY_PERIOD = 2 hours;

    mapping(address => uint256) public staticPrices;

    constructor(
        address _usdt,
        address _usdc,
        address _flx,
        address _kyc,
        address _emergencyWithdrawAdmin,
        address _adminManager,
        address _initialOwner
    ) Ownable(_initialOwner) WithAdminManager(_adminManager) 
      EmergencyWithdrawAdmin(_emergencyWithdrawAdmin) WithKYCRegistry(_kyc) {
        require(
            _usdt != address(0) &&
            _usdc != address(0) &&
            _flx != address(0),
            "Invalid token address"
        );
        usdt = _usdt;
        usdc = _usdc;
        flx = _flx;
    }

    function setKYCRegistry(
        address _kyc
    ) external override onlyOwner {
        _setKYCRegistry(_kyc);
    }

    function setAdminManager (
        address _adminManager
    ) external override onlyOwner {
        _setAdminManager(_adminManager);
    }

    function setClaimStartTime(
        uint256 idoId,
        uint64 _claimStartTime
    ) external onlyAdmin {
        idoSchedules[idoId].claimStartTime = _claimStartTime;
        emit ClaimStartTimeSet(idoId, _claimStartTime);
    }

    function setTgeTime(
        uint256 idoId,
        uint64 _tgeTime
    ) external onlyAdmin {
        idoSchedules[idoId].tgeTime = _tgeTime;
        emit TgeTimeSet(idoId, _tgeTime);
    }

    function setIdoTime(
        uint256 idoId,
        uint64 _idoStartTime,
        uint64 _idoEndTime
    ) external onlyAdmin {
        idoSchedules[idoId].idoStartTime = _idoStartTime;
        idoSchedules[idoId].idoEndTime = _idoEndTime;
        emit IdoTimeSet(idoId, _idoStartTime, _idoEndTime);
    }

    function setTokenAddress(
        uint256 idoId,
        address _address
    ) external onlyAdmin {
        IDO storage ido = idos[idoId];
        ido.info.tokenAddress = _address;
        emit TokenAddressSet(idoId, _address);
    }

    function setStaticPrice(address token, uint256 price) external onlyAdmin {
        staticPrices[token] = price;
        emit StaticPriceSet(token, price);
    }

    function setTwapPriceUsdt(
        uint256 idoId,
        uint256 twapPriceUsdt
    ) external onlyAdmin {
        idoPricing[idoId].twapPriceUsdt = twapPriceUsdt;
        emit TwapSet(idoId, twapPriceUsdt);
    }

    function createIDO(IDOInput calldata idoInput) external onlyAdmin returns (uint256) {
        IDOInfo memory _idoInputInfo = idoInput.info;
        IDOSchedules memory _idoInputSchedules = idoInput.schedules;
        RefundPolicy memory _inputRefundPolicy = idoInput.refundPolicy;
        RefundPenalties memory _inputRefundPenalties = idoInput.refundPenalties;
        
        require(_idoInputSchedules.idoStartTime < _idoInputSchedules.idoEndTime, "Invalid time range");
        require(_idoInputInfo.totalAllocationByUser > 0, "Invalid allocation");
        require(_idoInputInfo.totalAllocation > 0, "Invalid allocation");
        require(idoInput.initialPriceUsdt > 0, "Invalid initial price");
        require(_idoInputSchedules.vestingDuration > 0, "Invalid vesting duration");
        require(_idoInputSchedules.unlockInterval > 0, "Invalid unlock interval");
        require(_idoInputSchedules.unlockInterval <= _idoInputSchedules.vestingDuration, "Invalid unlock interval");

        // TODO schedule validation: tge time, intervals, cliff, etc. Check that they make sense

        uint256 idoId = ++idoCount;

        idoSchedules[idoId] = IDOSchedules({
            idoStartTime: _idoInputSchedules.idoStartTime,
            idoEndTime: _idoInputSchedules.idoEndTime,
            claimStartTime: 0,
            tgeTime: 0,
            cliffDuration: _idoInputSchedules.cliffDuration,
            vestingDuration: _idoInputSchedules.vestingDuration,
            unlockInterval: _idoInputSchedules.unlockInterval,
            tgeUnlockPercent: _idoInputSchedules.tgeUnlockPercent,
            timeoutForRefundAfterVesting: _idoInputSchedules.timeoutForRefundAfterVesting,
            twapCalculationWindowHours: _idoInputSchedules.twapCalculationWindowHours
        });

        idoRefundInfo[idoId] = IDORefundInfo({
            totalRefunded: 0,
            refundedBonus: 0,
            totalRefundedUSDT: 0,
            refundPenalties: RefundPenalties({
                fullRefundPenalty: _inputRefundPenalties.fullRefundPenalty,
                fullRefundPenaltyBeforeTge: _inputRefundPenalties.fullRefundPenaltyBeforeTge,
                refundPenalty: _inputRefundPenalties.refundPenalty
            }),
            refundPolicy: RefundPolicy({
                fullRefundDuration: _inputRefundPolicy.fullRefundDuration,
                isRefundIfClaimedAllowed: _inputRefundPolicy.isRefundIfClaimedAllowed,
                isRefundUnlockedPartOnly: _inputRefundPolicy.isRefundUnlockedPartOnly,
                isRefundInCliffAllowed: _inputRefundPolicy.isRefundInCliffAllowed,
                isFullRefundBeforeTGEAllowed: _inputRefundPolicy.isFullRefundBeforeTGEAllowed,
                isPartialRefundInCliffAllowed: _inputRefundPolicy.isPartialRefundInCliffAllowed,
                isFullRefundInCliffAllowed: _inputRefundPolicy.isFullRefundInCliffAllowed,
                isPartialRefundInVestingAllowed: _inputRefundPolicy.isPartialRefundInVestingAllowed,
                isFullRefundInVestingAllowed: _inputRefundPolicy.isFullRefundInVestingAllowed
            })
        });

        idoPricing[idoId] = IDOPricing({
            initialPriceUsdt: idoInput.initialPriceUsdt,
            fullRefundPriceUsdt: idoInput.fullRefundPriceUsdt,
            twapPriceUsdt: 0
        });

        idos[idoId] = IDO({
            totalParticipants: 0,
            totalRaisedUSDT: 0,
            info: IDOInfo({
                projectId: _idoInputInfo.projectId,
                tokenAddress: _idoInputInfo.tokenAddress,
                totalAllocated: 0,
                minAllocation: _idoInputInfo.minAllocation,
                totalAllocationByUser: _idoInputInfo.totalAllocationByUser,
                totalAllocation: _idoInputInfo.totalAllocation
            }),
            bonuses: IDOBonuses({
                phase1BonusPercent: idoInput.bonuses.phase1BonusPercent,
                phase2BonusPercent: idoInput.bonuses.phase2BonusPercent,
                phase3BonusPercent: idoInput.bonuses.phase3BonusPercent
            })
        });

        emit IDOCreated(idoId, _idoInputInfo.projectId, _idoInputSchedules.idoStartTime, _idoInputSchedules.idoEndTime);
        return idoId;
    }

    function getTokensAvailableToClaim(
        uint256 idoId,
        address user
    ) external view returns (uint256) {
        (uint256 tokens, uint256 bonus) = _getTokensAvailableToClaim(idoSchedules[idoId], userInfo[idoId][user]);
        return tokens + bonus;
    }

    function _getTokensAvailableToClaim(
        IDOSchedules memory schedules,
        UserInfo memory user
    ) internal view returns (uint256, uint256) {
        uint256 unlockedPercent = _getUnlockedPercent(schedules);
        require(unlockedPercent > 0, "Tokens are locked");

        uint256 unlockedWithoutBonus = (user.allocatedTokens - user.allocatedBonus).mulDiv(unlockedPercent, HUNDRED_PERCENT);
        uint256 unlockedBonus = user.allocatedBonus.mulDiv(unlockedPercent, HUNDRED_PERCENT);

        uint256 claimedTokensWOBonus = user.claimedTokens - user.claimedBonus;

        return (
            unlockedWithoutBonus > claimedTokensWOBonus + user.refundedTokens ? unlockedWithoutBonus - claimedTokensWOBonus - user.refundedTokens : 0,
            unlockedBonus > user.claimedBonus + user.refundedBonus ? unlockedBonus - user.claimedBonus - user.refundedBonus : 0
        );
    }

    function getTokensAvailableToRefund(
        uint256 idoId,
        address user,
        bool fullRefund
    ) external view returns (uint256 amount) {
        return _getTokensAvailableToRefund(
            idoSchedules[idoId],
            idoRefundInfo[idoId],
            idoPricing[idoId],
            userInfo[idoId][user],
            fullRefund
        );
    }

    function getTokensAvailableToRefundWithPenalty(
        uint256 idoId,
        address user,
        bool fullRefund
    ) external view returns (uint256 totalRefundAmount, uint256 refundPercentAfterPenalty) {
        IDOSchedules memory schedules = idoSchedules[idoId];
        IDORefundInfo memory refundInfo = idoRefundInfo[idoId];
        IDOPricing memory pricing = idoPricing[idoId];
        UserInfo memory userInfoLocal = userInfo[idoId][user];

        totalRefundAmount = _getTokensAvailableToRefund(schedules, refundInfo, pricing, userInfoLocal, fullRefund);
        refundPercentAfterPenalty = _getRefundPercentAfterPenalty(schedules, refundInfo, pricing, userInfoLocal, fullRefund);
    }

    function _getTokensAvailableToRefund(
        IDOSchedules memory schedules,
        IDORefundInfo memory refundInfo,
        IDOPricing memory pricing,
        UserInfo memory user,
        bool fullRefund
    ) internal view returns (uint256 tokensToRefund) {
        if (!_isRefundAllowed(schedules, refundInfo, pricing, user, fullRefund)) {
            return 0;
        }

        uint256 totalToRefund;
        if (fullRefund && !refundInfo.refundPolicy.isRefundUnlockedPartOnly) {
            totalToRefund = user.allocatedTokens - user.allocatedBonus;
        } else {
            uint256 unlockedPercent = _getUnlockedPercent(schedules);
            totalToRefund = (user.allocatedTokens - user.allocatedBonus).mulDiv(unlockedPercent, HUNDRED_PERCENT);
        }

        uint tokensTaken = user.refundedTokens + user.claimedTokens;
        return (totalToRefund > tokensTaken ? totalToRefund - tokensTaken : 0);
    }

    function _getRefundPercentAfterPenalty(
        IDOSchedules memory schedules, 
        IDORefundInfo memory refundInfo, 
        IDOPricing memory pricing,
        UserInfo memory user,
        bool fullRefund
    ) internal view returns (uint256 refundPercentAfterPenalty) {
        if (!_isRefundAllowed(schedules, refundInfo, pricing, user, fullRefund)) {
            return 0;
        }

        uint256 penalty;

        if (_isTWAPWindowFinished(schedules)
            && !_isFullRefundWindowFinished(schedules, refundInfo.refundPolicy)
            && _isTWAPUndervalued(pricing)
        ) {
            penalty = 0;
        } else if (fullRefund) {
            penalty = schedules.tgeTime == 0 || !_isTGEStarted(schedules) ? 
                refundInfo.refundPenalties.fullRefundPenaltyBeforeTge : 
                refundInfo.refundPenalties.fullRefundPenalty;
        } else {
            penalty = refundInfo.refundPenalties.refundPenalty;
        }

        return HUNDRED_PERCENT - penalty;
    }

    // TODO review and fix
    function claimTokens(uint256 idoId) external nonReentrant {
        IDO memory ido = idos[idoId];
        IDOSchedules memory schedules = idoSchedules[idoId];
        UserInfo storage user = userInfo[idoId][msg.sender];

        require(
            schedules.claimStartTime > 0 && block.timestamp >= schedules.claimStartTime,
            "Claim not started"
        );

        require(ido.info.tokenAddress != address(0), 'Token is not set yet');

        ERC20 token = ERC20(ido.info.tokenAddress);

        (uint256 tokensToClaim, uint256 bonusesToClaim) = _getTokensAvailableToClaim(schedules, user);
        uint256 userTokensAmountToClaim = tokensToClaim + bonusesToClaim;
        require(userTokensAmountToClaim > 0, "Nothing to claim");
        require(userTokensAmountToClaim + user.refundedTokens + user.refundedBonus + user.claimedTokens <= user.allocatedTokens, "Claim exceeds allocated tokens");

        uint256 totalTokensInTokensDecimals = userTokensAmountToClaim.mulDiv(10 ** token.decimals(), DECIMALS);

        user.claimed = true;
        user.claimedTokens += userTokensAmountToClaim;
        user.claimedBonus += bonusesToClaim;

        require(
            token.transfer(msg.sender, totalTokensInTokensDecimals),
            "Token transfer failed"
        );

        emit TokensClaimed(idoId, msg.sender, userTokensAmountToClaim);
    }

    function _currentPhase(IDO memory ido) internal pure returns (Phase) {
        require(ido.info.totalAllocation > 0, "Invalid total allocation");

        uint256 oneThird = ido.info.totalAllocation / 3;

        if (ido.info.totalAllocated < oneThird) {
            return Phase.Phase1;
        } else if (ido.info.totalAllocated < 2 * oneThird) {
            return Phase.Phase2;
        } else {
            return Phase.Phase3;
        }
    }

    function currentPhase(uint256 idoId) external view returns (Phase) {
        IDO memory ido = idos[idoId];
        return _currentPhase(ido);
    }

    function _getPhaseBonus(IDO memory ido) internal pure returns (uint256, Phase) {
        Phase phase = _currentPhase(ido);
        if (phase == Phase.Phase1) return (ido.bonuses.phase1BonusPercent, phase);
        if (phase == Phase.Phase2) return (ido.bonuses.phase2BonusPercent, phase);
        return (ido.bonuses.phase3BonusPercent, phase);
    }

    function getUnlockedPercent(uint256 idoId) public view returns (uint256) {
        return _getUnlockedPercent(idoSchedules[idoId]);
    }

    // * Percentage of tokens that are unlocked now, including TGE and vesting
    function _getUnlockedPercent(
        IDOSchedules memory schedules
    ) internal view returns (uint256) {
        if (schedules.tgeTime == 0 || !_isTGEStarted(schedules)) {
            return 0;
        }

        if (!_isCliffFinished(schedules)) {
            return schedules.tgeUnlockPercent;
        }

        uint256 vestingEndTime = schedules.tgeTime + schedules.cliffDuration + schedules.vestingDuration;

        if (block.timestamp > vestingEndTime) {
            return HUNDRED_PERCENT;
        }

        uint256 vestingTime = block.timestamp - schedules.tgeTime - schedules.cliffDuration;
        uint256 intervalsCompleted = vestingTime / schedules.unlockInterval;
        uint256 totalIntervals = _getNumberOfVestingIntervals(schedules);

        uint256 vestingPercent = intervalsCompleted.mulDiv(
            HUNDRED_PERCENT - schedules.tgeUnlockPercent,
            totalIntervals
        );

        return schedules.tgeUnlockPercent + vestingPercent;
    }

    function _getNumberOfVestingIntervals(
        IDOSchedules memory schedules
    ) internal pure returns (uint256) {
        uint256 totalIntervals = schedules.vestingDuration / schedules.unlockInterval;

        if (schedules.vestingDuration % schedules.unlockInterval != 0) {
            totalIntervals += 1;
        }

        return totalIntervals;
    }

    function isRefundAvailable(uint256 idoId, bool fullRefund) external view returns (bool) {
        return _isRefundAllowed(idoSchedules[idoId], idoRefundInfo[idoId], idoPricing[idoId], userInfo[idoId][msg.sender], fullRefund);
    }

    function _isRefundAllowed(
        IDOSchedules memory schedules, 
        IDORefundInfo memory refundInfo, 
        IDOPricing memory pricing, 
        UserInfo memory user, 
        bool fullRefund
    ) internal view returns (bool) {
        
        if (!_isTGEStarted(schedules)) {
            return _isRefundBeforeTGEAllowed(fullRefund, refundInfo);
        }
        if (_isTWAPWindowFinished(schedules) &&
            !_isFullRefundWindowFinished(schedules, refundInfo.refundPolicy)) 
        {
            return _isTWAPUndervalued(pricing) && fullRefund;
        }
        if (!_isCliffFinished(schedules)) {
            return _isCliffRefundAllowed(fullRefund, refundInfo);
        }
        if (_isCliffFinished(schedules)) {
            return _isRefundInVestingAllowed(fullRefund, refundInfo);
        }
        if (!refundInfo.refundPolicy.isRefundIfClaimedAllowed && user.claimed) {
            return false;
        }

        return true;
    }

    function processRefund(uint256 idoId, bool fullRefund) external nonReentrant {
        IDOSchedules memory schedules = idoSchedules[idoId];
        IDORefundInfo memory refundInfo = idoRefundInfo[idoId];
        IDOPricing memory pricing = idoPricing[idoId];
        UserInfo memory user = userInfo[idoId][msg.sender];
        UserInfo storage userStorage = userInfo[idoId][msg.sender];

        require(_isRefundAllowed(schedules, refundInfo, pricing, user, fullRefund), "Refund is not available right now");

        uint256 tokensToRefund = _getTokensAvailableToRefund(
            schedules,
            refundInfo,
            pricing,
            user,
            fullRefund
        );
        uint256 percentToReturn = _getRefundPercentAfterPenalty(
            schedules,
            refundInfo,
            pricing,
            user,
            fullRefund
        );

        require(tokensToRefund > 0, "Nothing to refund");

        uint256 bonusToSub;
        bonusToSub = user.allocatedBonus - user.refundedBonus - user.claimedBonus;

        // TODO refundedBonus разве не бесполезная переменная вообще? Она не исчисляет РЕАЛЬНЫЕ выведенные токены, потому что бонус не рефандится
        userStorage.refundedBonus += bonusToSub;
        userStorage.refundedTokens += tokensToRefund;

        idoRefundInfo[idoId].totalRefunded += tokensToRefund;
        // TODO здесь точно так же
        idoRefundInfo[idoId].refundedBonus += bonusToSub;

        uint256 refundedUsdt = _convertToUSDT(tokensToRefund, pricing.initialPriceUsdt).mulDiv(percentToReturn, HUNDRED_PERCENT);

        idoRefundInfo[idoId].totalRefundedUSDT += refundedUsdt;
        userStorage.refundedUsdt += refundedUsdt;

        uint256 investedTokensToRefund = _convertFromUSDT(refundedUsdt, staticPrices[user.investedToken]);
        ERC20 token = ERC20(user.investedToken);
        uint256 investedTokensToRefundScaled = investedTokensToRefund.mulDiv(10 ** token.decimals(), DECIMALS);
        
        require(
            user.investedTokenAmountRefunded + investedTokensToRefundScaled <=
                user.investedTokenAmount,
            "Refund exceeds invested amount"
        );

        userStorage.investedTokenAmountRefunded += investedTokensToRefundScaled;

        require(
            token.transfer(msg.sender, investedTokensToRefundScaled),
            "Token transfer failed"
        );

        emit Refund(idoId, msg.sender, tokensToRefund, investedTokensToRefundScaled);
    }

    function invest(
        uint256 idoId,
        uint256 amount,
        address tokenIn
    ) external nonReentrant onlyKYC {
        require(
            tokenIn == usdt || tokenIn == usdc || tokenIn == flx,
            "Invalid token"
        );

        IDO storage ido = idos[idoId];
        IDOSchedules memory schedules = idoSchedules[idoId];
        IDORefundInfo memory refundInfo = idoRefundInfo[idoId];
        IDOPricing memory pricing = idoPricing[idoId];
        UserInfo storage user = userInfo[idoId][msg.sender];

        require(
            ido.info.totalAllocated < ido.info.totalAllocation && block.timestamp <= schedules.idoEndTime,
            "IDO is ended"
        );
        require(
            block.timestamp >= schedules.idoStartTime,
            "IDO is not started yet"
        );
        require(pricing.initialPriceUsdt > 0, "Initial price not set");
        require(user.investedToken == address(0), "You already invested");

        ido.totalParticipants ++;

        uint256 staticPrice = staticPrices[tokenIn];
        require(staticPrice > 0, "Static price not set");

        ERC20 _tokenIn = ERC20(tokenIn);
        uint256 normalizedAmount = amount.mulDiv(DECIMALS, 10 ** _tokenIn.decimals());
        uint256 amountInUSD = _convertToUSDT(normalizedAmount, staticPrice);

        require(amountInUSD >= ido.info.minAllocation, "Amount must be greater than min allocation");

        (uint256 bonusPercent, Phase phaseNow) = _getPhaseBonus(ido);

        user.investedUsdt += amountInUSD;
        user.investedTokenAmount += amount;
        user.investedTime = uint64(block.timestamp);
        user.investedPhase = phaseNow;
        user.investedToken = tokenIn;

        uint256 bonusesMultiplier = bonusPercent + HUNDRED_PERCENT;
        uint256 tokensBought = _convertFromUSDT(amountInUSD, pricing.initialPriceUsdt)
            .mulDiv(bonusesMultiplier, HUNDRED_PERCENT);
        uint256 tokensBonus = tokensBought - _convertFromUSDT(amountInUSD, pricing.initialPriceUsdt);

        require(
            tokensBought + user.allocatedTokens - user.refundedTokens - user.refundedBonus <= ido.info.totalAllocationByUser,
            "Exceeds max allocation per user"
        );
        require(
            tokensBought + ido.info.totalAllocated - refundInfo.totalRefunded - refundInfo.refundedBonus <= ido.info.totalAllocation,
            "Exceeds total allocation"
        );

        user.allocatedTokens += tokensBought;
        user.allocatedBonus += tokensBonus;
        ido.info.totalAllocated += tokensBought;
        ido.totalRaisedUSDT += amountInUSD;

        require(
            _tokenIn.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        emit Investment(idoId, msg.sender, amountInUSD, tokenIn, normalizedAmount, tokensBought, tokensBonus);
    }

    function _convertToUSDT(
        uint256 amount,
        uint256 priceOfToken
    ) internal pure returns (uint256 amountInUSDT) {
        require(priceOfToken > 0, "Price must be greater than zero");
        amountInUSDT = amount.mulDiv(priceOfToken, PRICE_DECIMALS);
    }

    function _convertFromUSDT(
        uint256 amountUSDT,
        uint256 priceOfToken
    ) internal pure returns (uint256 amountInToken) {
        require(priceOfToken > 0, "Price must be greater than zero");
        amountInToken = amountUSDT.mulDiv(PRICE_DECIMALS, priceOfToken);
    }

    function _getUserAvailableTokens(UserInfo memory user) internal pure returns (uint256) {
        return user.allocatedTokens - user.claimedTokens - user.refundedTokens;
    }

    function getUserInfo(
        uint256 idoId,
        address userAddr
    )
        external
        view
        returns (
            uint256 investedUsdt,
            uint256 allocatedTokens,
            uint256 claimedTokens,
            uint256 refundedTokens,
            bool claimed
        )
    {
        UserInfo storage info = userInfo[idoId][userAddr];
        return (
            info.investedUsdt,
            info.allocatedTokens,
            info.claimedTokens,
            info.refundedTokens,
            info.claimed
        );
    }


    function _isTGEStarted(IDOSchedules memory _idoSchedules) internal view returns (bool) {
        uint64 tgeTime = _idoSchedules.tgeTime;
        return tgeTime > 0 && block.timestamp >= tgeTime;
    }

    function _isCliffFinished(IDOSchedules memory _idoSchedules) internal view returns (bool) {
        uint64 tgeTime = _idoSchedules.tgeTime;
        return tgeTime > 0 && block.timestamp >= tgeTime + _idoSchedules.cliffDuration;
    }

    function _isTWAPWindowFinished(IDOSchedules memory _idoSchedules) internal view returns (bool) {
        uint64 tgeTime = _idoSchedules.tgeTime;
        return tgeTime > 0 && block.timestamp >= tgeTime + _idoSchedules.twapCalculationWindowHours * 1 hours;
    }

    function _isFullRefundWindowFinished(IDOSchedules memory _idoSchedules, RefundPolicy memory _refundPolicy) internal view returns (bool) {
        uint64 tgeTime = _idoSchedules.tgeTime;
        return tgeTime > 0 && block.timestamp >= tgeTime + _idoSchedules.twapCalculationWindowHours * 1 hours + _refundPolicy.fullRefundDuration;
    }

    function _isTWAPUndervalued(IDOPricing memory _idoPricing) internal pure returns (bool) {
        return _idoPricing.twapPriceUsdt > 0 && _idoPricing.twapPriceUsdt <= _idoPricing.fullRefundPriceUsdt;
    }

    function _isRefundBeforeTGEAllowed(bool fullRefund, IDORefundInfo memory refundInfo) internal pure returns (bool) {
        if (fullRefund) {
            return refundInfo.refundPolicy.isFullRefundBeforeTGEAllowed;
        } else {
            return false;
        }
    }

    function _isCliffRefundAllowed(bool fullRefund, IDORefundInfo memory refundInfo) internal pure returns (bool) {
        if (fullRefund) {
            return refundInfo.refundPolicy.isFullRefundInVestingAllowed;
        } else {
            return refundInfo.refundPolicy.isPartialRefundInVestingAllowed;
        }
    }

    function _isRefundInVestingAllowed(bool fullRefund, IDORefundInfo memory refundInfo) internal pure returns (bool) {
        if (fullRefund) {
            return refundInfo.refundPolicy.isFullRefundInVestingAllowed;
        } else {
            return refundInfo.refundPolicy.isPartialRefundInVestingAllowed;
        }
    }
}
