#property link          "https://www.earnforex.com/metatrader-scripts/close-all-orders/"
#property version       "1.02"
#property strict
#property copyright     "EarnForex.com - 2020-2025"
#property description   "A script to close all the open market orders."
#property description   ""
#property description   "WARNING: There is no guarantee that this script will work as intended. Use at your own risk."
#property description   ""
#property description   "Find more on www.EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"
#property show_inputs

enum ENUM_ORDER_TYPES
{
    ALL_ORDERS = 1, // ALL ORDERS
    ONLY_BUY = 2,   // BUY ONLY
    ONLY_SELL = 3   // SELL ONLY
};

enum ENUM_SORT_ORDERS
{
    SORT_ORDERS_NO, // No sorting (the fastest method)
    SORT_ORDERS_ABS_PROFIT_ASC, // Smaller profit/loss first
    SORT_ORDERS_ABS_PROFIT_DESC, // Larger profit/loss first
    SORT_ORDERS_PROFIT_ASC, // From biggest loss to biggest profit
    SORT_ORDERS_PROFIT_DESC // From biggest profit to biggest loss
};

input bool OnlyCurrentSymbol = false; // Close only instrument in the chart
input ENUM_ORDER_TYPES OrderTypeFilter = ALL_ORDERS; // Type of orders to close
input bool OnlyInProfit = false;      // Close only orders in profit
input bool OnlyInLoss = true;         // Close only orders in loss
input bool OnlyMagicNumber = false;   // Close only orders matching the magic number
input int MagicNumber = 0;            // Matching magic number
input bool OnlyWithComment = false;   // Close only orders with the following comment
input string MatchingComment = "";    // Matching comment
input int Slippage = 2;               // Slippage
input int Delay = 0;                  // Delay to wait between closing attempts (in milliseconds)
input int Retries = 10;               // How many times to try closing each order
input ENUM_SORT_ORDERS Sort = SORT_ORDERS_NO; // Sort orders for closing?
input int ClosePercentage = 100;      // Close percentage

// Global variables:
double PositionsByProfit[][2]; // To sort orders by floating profit (if necessary).

void OnStart()
{
    int total = OrdersTotal();
    // Log the total number of orders.
    Print("Total orders: ", total);
    int cnt = 0; // Number of open orders found during filtering.

    // Start a loop to scan all the orders.
    // The loop starts from the last, otherwise it could skip orders.
    for (int i = total - 1; i >= 0; i--)
    {
        // If the order cannot be selected throw and log an error.
        if (OrderSelect(i, SELECT_BY_POS) == false)
        {
            Print("ERROR - Unable to select the order - ", GetLastError());
            break;
        }

        // Check if the order matches the filter and if not skip the order and move to the next.
        if ((OrderType() != OP_BUY) && (OrderType() != OP_SELL)) continue; // Skip pending orders.
        if ((OrderTypeFilter == ONLY_SELL) && (OrderType() == OP_BUY)) continue; // Don't act if the order is a Buy, and it was selected to only close Sell orders.
        if ((OrderTypeFilter == ONLY_BUY) && (OrderType() == OP_SELL)) continue; // Don't act if the order is a Sell, and it was selected to only close Buy orders.
        if ((OnlyCurrentSymbol) && (OrderSymbol() != Symbol())) continue;
        if ((OnlyInProfit) && (OrderProfit() <= 0)) continue;
        if ((OnlyInLoss) && (OrderProfit() >= 0)) continue;
        if ((OnlyMagicNumber) && (OrderMagicNumber() != MagicNumber)) continue;
        if ((OnlyWithComment) && (StringCompare(OrderComment(), MatchingComment) != 0)) continue;

        if (Sort != SORT_ORDERS_NO)
        {
            cnt++;

            ArrayResize(PositionsByProfit, cnt, 100); // Reserve extra physical memory to increase the resizing speed.

            double profit = OrderProfit();
            if ((Sort == SORT_ORDERS_ABS_PROFIT_ASC) || (Sort == SORT_ORDERS_ABS_PROFIT_DESC))
            {
                profit = MathAbs(profit);
            }

            PositionsByProfit[cnt - 1][0] = profit;
            PositionsByProfit[cnt - 1][1] = OrderTicket();
        }
        else
        {
            CloseOrder();
        }
    }

    if (Sort != SORT_ORDERS_NO) // If some sorting is required, the script hasn't closed anything yet.
    {
        if ((Sort == SORT_ORDERS_ABS_PROFIT_ASC) || (Sort == SORT_ORDERS_PROFIT_ASC)) ArraySort(PositionsByProfit, WHOLE_ARRAY, 0, MODE_ASCEND);
        else if ((Sort == SORT_ORDERS_ABS_PROFIT_DESC) || (Sort == SORT_ORDERS_PROFIT_DESC)) ArraySort(PositionsByProfit, WHOLE_ARRAY, 0, MODE_DESCEND);
        // It's time to actually close the orders based on the collected info.
        total = ArrayRange(PositionsByProfit, 0);
        for (int i = 0; i < total; i++)
        {
            CloseOrder((int)PositionsByProfit[i][1]);
        }
    }
}

void CloseOrder(int ticket = 0)
{
    if (ticket != 0) // Otherwise, already selected.
    {
        if (!OrderSelect(ticket, SELECT_BY_TICKET))
        {
            Print("ERROR - Unable to select the order by ticket. Ticket: ", ticket, ", Error: ", GetLastError());
            return;
        }
    }

    double CloseVolume = OrderLots();
    if (ClosePercentage < 100)
    {
        CloseVolume = (CloseVolume * ClosePercentage) / 100.0;
        double vol_min = SymbolInfoDouble(OrderSymbol(), SYMBOL_VOLUME_MIN);
        double vol_step = SymbolInfoDouble(OrderSymbol(), SYMBOL_VOLUME_STEP);

        if (CloseVolume < vol_min) CloseVolume = vol_min;
        else
        {
            double steps = 0;
            if (vol_step != 0) steps = CloseVolume / vol_step;
            if (MathFloor(steps) < steps)
            {
                CloseVolume = MathFloor(steps) * vol_step; // Close the smallest part of the volume possible.
            }
        }
    }

    // Try to close the trade in a cycle to overcome temporary failures.
    for (int try = 0; try < Retries; try++)
    {
        // Result variable, to check if the operation is successful or not.
        bool result = false;

        // Update the exchange rates before closing the orders.
        RefreshRates();
        // Bid and Ask price for the order's symbol.
        double BidPrice = MarketInfo(OrderSymbol(), MODE_BID);
        double AskPrice = MarketInfo(OrderSymbol(), MODE_ASK);

        // Closing the order using the correct price depending on the order's type.
        if (OrderType() == OP_BUY)
        {
            result = OrderClose(OrderTicket(), CloseVolume, BidPrice, Slippage);
        }
        if (OrderType() == OP_SELL)
        {
            result = OrderClose(OrderTicket(), CloseVolume, AskPrice, Slippage);
        }

        // If there was an error, log it.
        if (!result) Print("ERROR - Unable to close the order - ", OrderTicket(), " - Error ", GetLastError());

        Sleep(Delay);

        if (result) break; // Finished with this order.
    }
}
//+------------------------------------------------------------------+