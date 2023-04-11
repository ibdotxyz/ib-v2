# Iron Bank Extension

Iron Bank extension is an external contract that provides multiple useful operations for user to manager their positions. It integrates Uniswap v2 and Uniswap v3. It also allows users to combine multiple operations into one transaction. The provided operations include:

### Supply Native Token

Help user wrap Ether into WETH and supply it into Iron Bank.

### Borrow Native Token

Help user borrow WETH from Iron Bank and unwrap it to Ether.

### Redeem Native Token

Help user redeem WETH from Iron Bank and unwrap it to Ether.

### Repay Native Token

Help user wrap Ether into WETH and repay it into Iron Bank. If user repays more than borrow balance, the excessive amount will return to user.

### Add collateral

Help user supply asset and enter market. Need to be careful for the collateral cap.

### Borrow

Help user borrow asset.

### Leverage Long Through Uniswap v3

Help user leverage long an asset against another asset thorough Uniswap v3. Need to be careful for the collateral cap.

### Leverage Short Through Uniswap v3

Help user leverage short an asset against another asset thorough Uniswap v3. Need to be careful for the collateral cap.

### Swap Debt Through Uniswap v3

Help user swap debt through Uniswap v3.

### Swap Collateral Thorugh Uniswap v3

Help user swap collateral through Uniswap v3. Need to be careful for the collateral cap.

### Leverage Long Through Uniswap v2

Help user leverage long an asset against another asset thorough Uniswap v2. Need to be careful for the collateral cap.

### Leverage Short Through Uniswap v2

Help user leverage short an asset against another asset thorough Uniswap v2. Need to be careful for the collateral cap.

### Swap Debt Through Uniswap v2

Help user swap debt through Uniswap v2.

### Swap Collateral Thorugh Uniswap v2

Help user swap collateral through Uniswap v2. Need to be careful for the collateral cap.

## Techinical Explanation

There are several operations involving swaps through Uniswap, but they can be generally divided into two categories, exact input swap and exact output swap.

### Exact Output Swap

Before we start explaining the exact output swap, let's take an example: debt swap. A user has borrowed 100 DAI and he wants to exchange his DAI debt for USDT. First, we flash borrow 100 DAI from Uniswap and we repay user's DAI debt on Iron Bank. Next, we borrow from Iron Bank the amount of USDT we need to repay to Uniswap. Last, we repay the USDT to complete the flash borrow.

![debt swap](debt_swap.png)

From Uniswap's point of view, this is swapping a maximum possible of USDT for a fixed amount of DAI. In addition to debt swap, open long position and close long position also belong to this category.

Although the above example for Uniswap is to swap USDT for a fixed amount of DAI, in fact, because through flash swap, we will first get 100 DAI we want, and use the same recursive method as in the [Uniswap v3 router](https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/SwapRouter.sol) to process data in reverse. In the Uniswap v2 router, flash swap is not actually used, but the most basic swap is used after calculating the amounts needed to pass in (data.length equals to 0). Therefore, when we use the recursive method to process Uniswap v2 flash borrow, what we return in `getAmountsIn` function will be reversed with what is returned in [Uniswap v2 library](https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol).

### Exact Input Swap

Let's look at another example: collateral swap. A user has supplied 100 DAI as collateral and he wants to exchange his DAI for USDT. First, we flash borrow some USDT by specifying that we will repay 100 DAI and supply these USDT for user to Iron Bank. Next, we redeem 100 DAI from Iron Bank. Last, we repay 100 DAI to Uniswap to complete the flash borrow.

![collateral swap](collateral_swap.png)

From Uniswap's point of view, this is swapping a fixed amount of DAI for a minimum possible of USDT.
In addition to collateral swap, open short position and close short position also belong to this category.

For exact input swap, although we already know the amount to pay, we can't pay it at the beginning, because we can't redeem or borrow for users until we supply or repay for users in the last step of the swap. Therefore, we still need to use the same recursive method as the exact output swap.
