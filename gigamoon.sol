// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./Context.sol";
import "./Address.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";

contract GigaMoon is Context, IERC20, GMOwnable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _isLottery;
    address[] private _excluded;

    string private _name = "GigaMoon";
    string private _symbol = "GIGAMOON";
    uint8 private _decimals = 9;

    address public LotteryAddress = 0xDA0679f837d0c3489C8f061cFEAC7752Fdab097E;

    uint256 private _MAX = ~uint256(0);
    uint256 private _GRANULARITY = 100;

    uint256 private _tTotal = 10000000000000000 * 10**6 * 10**9;
    uint256 private _rTotal = (_MAX - (_MAX % _tTotal));

    uint256 private _tFeeTotal = 2;
    uint256 private _tBurnTotal = 3;
    uint256 private _tLotteryTotal = 5;

    uint256 public _TAX_FEE = 0;
    uint256 public _BURN_FEE = 0;
    uint256 public _LOTTERY_FEE = 0;

    // Track original fees to bypass fees for lottery account
    uint256 private ORIG_TAX_FEE;
    uint256 private ORIG_BURN_FEE;
    uint256 private ORIG_LOTTERY_FEE;

    constructor() {
        _isLottery[LotteryAddress] = true;
        _rOwned[_msgSender()] = _rTotal;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint256) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "TOKEN20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "TOKEN20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function isLottery(address account) public view returns (bool) {
        return _isLottery[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function totalBurn() public view returns (uint256) {
        return _tBurnTotal;
    }

    function totalLottery() public view returns (uint256) {
        return _tLotteryTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeAccount(address account) external onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeAccount(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function setAsLotteryAccount(address account) external onlyOwner() {
        require(!_isLottery[account], "Account is already lottery account");
        _isLottery[account] = true;
        LotteryAddress = account;
    }

    function burn(uint256 _value) public {
        _burn(msg.sender, _value);
    }

    function updateFee(
        uint256 _txFee,
        uint256 _burnFee,
        uint256 _lotteryFee
    ) public onlyOwner() {
        _TAX_FEE = _txFee * 100;
        _BURN_FEE = _burnFee * 100;
        _LOTTERY_FEE = _lotteryFee * 100;
        ORIG_TAX_FEE = _TAX_FEE;
        ORIG_BURN_FEE = _BURN_FEE;
        ORIG_LOTTERY_FEE = _LOTTERY_FEE;
    }

    function _burn(address _who, uint256 _value) internal {
        require(_value <= _rOwned[_who]);
        _rOwned[_who] = _rOwned[_who].sub(_value);
        _tTotal = _tTotal.sub(_value);
        emit Transfer(_who, address(0), _value);
    }

    function mint(address account, uint256 amount) public onlyOwner() {
        _tTotal = _tTotal.add(amount);
        _rOwned[account] = _rOwned[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "TOKEN20: approve from the zero address");
        require(spender != address(0), "TOKEN20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(
            sender != address(0),
            "TOKEN20: transfer from the zero address"
        );
        require(
            recipient != address(0),
            "TOKEN20: transfer to the zero address"
        );
        require(amount > 0, "Transfer amount must be greater than zero");

        // Remove fees for transfers to and from lottery account or to excluded account
        bool takeFee = true;
        if (
            _isLottery[sender] ||
            _isLottery[recipient] ||
            _isExcluded[recipient]
        ) {
            takeFee = false;
        }

        if (!takeFee) removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn,
            uint256 tLottery
        ) = _getValues(tAmount);
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rLottery = tLottery.mul(currentRate);
        _standardTransferContent(sender, recipient, rAmount, rTransferAmount);
        _sendToLottery(tLottery, sender);
        _reflectFee(rFee, rBurn, rLottery, tFee, tBurn, tLottery);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _standardTransferContent(
        address sender,
        address recipient,
        uint256 rAmount,
        uint256 rTransferAmount
    ) private {
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn,
            uint256 tLottery
        ) = _getValues(tAmount);
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rLottery = tLottery.mul(currentRate);
        _excludedFromTransferContent(
            sender,
            recipient,
            tTransferAmount,
            rAmount,
            rTransferAmount
        );
        _sendToLottery(tLottery, sender);
        _reflectFee(rFee, rBurn, rLottery, tFee, tBurn, tLottery);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _excludedFromTransferContent(
        address sender,
        address recipient,
        uint256 tTransferAmount,
        uint256 rAmount,
        uint256 rTransferAmount
    ) private {
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn,
            uint256 tLottery
        ) = _getValues(tAmount);
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rLottery = tLottery.mul(currentRate);
        _excludedToTransferContent(
            sender,
            recipient,
            tAmount,
            rAmount,
            rTransferAmount
        );
        _sendToLottery(tLottery, sender);
        _reflectFee(rFee, rBurn, rLottery, tFee, tBurn, tLottery);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _excludedToTransferContent(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 rAmount,
        uint256 rTransferAmount
    ) private {
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        uint256 currentRate = _getRate();
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tBurn,
            uint256 tLottery
        ) = _getValues(tAmount);
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rLottery = tLottery.mul(currentRate);
        _bothTransferContent(
            sender,
            recipient,
            tAmount,
            rAmount,
            tTransferAmount,
            rTransferAmount
        );
        _sendToLottery(tLottery, sender);
        _reflectFee(rFee, rBurn, rLottery, tFee, tBurn, tLottery);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _bothTransferContent(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 rAmount,
        uint256 tTransferAmount,
        uint256 rTransferAmount
    ) private {
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    }

    function _reflectFee(
        uint256 rFee,
        uint256 rBurn,
        uint256 rLottery,
        uint256 tFee,
        uint256 tBurn,
        uint256 tLottery
    ) private {
        _rTotal = _rTotal.sub(rFee).sub(rBurn).sub(rLottery);
        _tFeeTotal = _tFeeTotal.add(tFee);
        _tBurnTotal = _tBurnTotal.add(tBurn);
        _tLotteryTotal = _tLotteryTotal.add(tLottery);
        _tTotal = _tTotal.sub(tBurn);
        emit Transfer(address(this), address(0), tBurn);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 tFee, uint256 tBurn, uint256 tLottery) =
            _getTBasics(tAmount, _TAX_FEE, _BURN_FEE, _LOTTERY_FEE);
        uint256 tTransferAmount =
            getTTransferAmount(tAmount, tFee, tBurn, tLottery);
        uint256 currentRate = _getRate();
        (uint256 rAmount, uint256 rFee) =
            _getRBasics(tAmount, tFee, currentRate);
        uint256 rTransferAmount =
            _getRTransferAmount(rAmount, rFee, tBurn, tLottery, currentRate);
        return (
            rAmount,
            rTransferAmount,
            rFee,
            tTransferAmount,
            tFee,
            tBurn,
            tLottery
        );
    }

    function _getTBasics(
        uint256 tAmount,
        uint256 taxFee,
        uint256 burnFee,
        uint256 lotteryFee
    )
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = ((tAmount.mul(taxFee)).div(_GRANULARITY)).div(100);
        uint256 tBurn = ((tAmount.mul(burnFee)).div(_GRANULARITY)).div(100);
        uint256 tLottery =
            ((tAmount.mul(lotteryFee)).div(_GRANULARITY)).div(100);
        return (tFee, tBurn, tLottery);
    }

    function getTTransferAmount(
        uint256 tAmount,
        uint256 tFee,
        uint256 tBurn,
        uint256 tLottery
    ) private pure returns (uint256) {
        return tAmount.sub(tFee).sub(tBurn).sub(tLottery);
    }

    function _getRBasics(
        uint256 tAmount,
        uint256 tFee,
        uint256 currentRate
    ) private pure returns (uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        return (rAmount, rFee);
    }

    function _getRTransferAmount(
        uint256 rAmount,
        uint256 rFee,
        uint256 tBurn,
        uint256 tLottery,
        uint256 currentRate
    ) private pure returns (uint256) {
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rLottery = tLottery.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rBurn).sub(rLottery);
        return rTransferAmount;
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _sendToLottery(uint256 tLottery, address sender) private {
        uint256 currentRate = _getRate();
        uint256 rLottery = tLottery.mul(currentRate);
        _rOwned[LotteryAddress] = _rOwned[LotteryAddress].add(rLottery);
        _tOwned[LotteryAddress] = _tOwned[LotteryAddress].add(tLottery);
        emit Transfer(sender, LotteryAddress, tLottery);
    }

    function removeAllFee() private {
        if (_TAX_FEE == 0 && _BURN_FEE == 0 && _LOTTERY_FEE == 0) return;

        ORIG_TAX_FEE = _TAX_FEE;
        ORIG_BURN_FEE = _BURN_FEE;
        ORIG_LOTTERY_FEE = _LOTTERY_FEE;

        _TAX_FEE = 0;
        _BURN_FEE = 0;
        _LOTTERY_FEE = 0;
    }

    function restoreAllFee() private {
        _TAX_FEE = ORIG_TAX_FEE;
        _BURN_FEE = ORIG_BURN_FEE;
        _LOTTERY_FEE = ORIG_LOTTERY_FEE;
    }

    function _getTaxFee() private view returns (uint256) {
        return _TAX_FEE;
    }
}
