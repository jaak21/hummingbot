# distutils: language=c++
from decimal import Decimal
import logging
import math
from typing import (
    List,
    Tuple,
    Optional,
    Dict
)

from hummingbot.core.clock cimport Clock
from hummingbot.logger import HummingbotLogger
from hummingbot.core.event.event_listener cimport EventListener
from hummingbot.core.data_type.limit_order cimport LimitOrder
from hummingbot.core.data_type.limit_order import LimitOrder
from hummingbot.core.network_iterator import NetworkStatus
from hummingbot.connector.exchange_base import ExchangeBase
from hummingbot.connector.exchange_base cimport ExchangeBase
from hummingbot.core.event.events import (
    OrderType,
    TradeType
)

from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.strategy_base import StrategyBase

from libc.stdint cimport int64_t
from libc.stdlib cimport rand, srand, RAND_MAX
from libc.time cimport time
from hummingbot.core.data_type.order_book cimport OrderBook
from datetime import datetime

from .asset_price_delegate cimport AssetPriceDelegate
from .asset_price_delegate import AssetPriceDelegate
from .get_trading_volume import TokenMetrics

NaN = float("nan")
s_decimal_zero = Decimal(0)
s_decimal_neg_one = Decimal(-1)
ds_logger = None
# weak pseudorandomness is good enough for now
srand(time(NULL))

cdef class VwapTradeStrategy(StrategyBase):
    OPTION_LOG_NULL_ORDER_SIZE = 1 << 0
    OPTION_LOG_REMOVING_ORDER = 1 << 1
    OPTION_LOG_ADJUST_ORDER = 1 << 2
    OPTION_LOG_CREATE_ORDER = 1 << 3
    OPTION_LOG_MAKER_ORDER_FILLED = 1 << 4
    OPTION_LOG_STATUS_REPORT = 1 << 5
    OPTION_LOG_MAKER_ORDER_HEDGED = 1 << 6
    OPTION_LOG_ALL = 0x7fffffffffffffff
    CANCEL_EXPIRY_DURATION = 60.0

    @classmethod
    def logger(cls) -> HummingbotLogger:
        global ds_logger
        if ds_logger is None:
            ds_logger = logging.getLogger(__name__)
        return ds_logger

    def __init__(self,
                 market_infos: List[MarketTradingPairTuple],
                 order_type: str = "limit",
                 floor_price: Optional[float] = None,
                 cancel_order_wait_time: Optional[float] = 60.0,
                 is_buy: bool = True,
                 time_delay: float = 10.0,
                 is_vwap = True,
                 num_individual_orders: int = 1,
                 num_trading_sessions: int = 1,
                 percent_slippage: float = 0,
                 order_percent_of_volume: float = 100,
                 total_order_amount: Decimal = Decimal("1.0"),
                 total_order_per_session: Decimal = Decimal("1.0"),
                 buzzer_price: Optional[float] = None,
                 buzzer_percent: float = 0.01,
                 logging_options: int = OPTION_LOG_ALL,
                 status_report_interval: float = 900,
                 trading_time_duration: float = 0.0,
                 bid_spread: Decimal = s_decimal_zero,
                 ask_spread: Decimal = s_decimal_zero,
                 order_levels: int = 1,
                 order_refresh_time: float = 30.0,
                 order_level_spread: Decimal = s_decimal_zero,
                 order_level_amount: Decimal = s_decimal_zero,
                 order_refresh_tolerance_pct: Decimal = s_decimal_neg_one,
                 filled_order_delay: float = 60.0,
                 inventory_skew_enabled: bool = False,
                 inventory_target_base_pct: Decimal = s_decimal_zero,
                 inventory_range_multiplier: Decimal = s_decimal_zero,
                 hanging_orders_enabled: bool = False,
                 hanging_orders_cancel_pct: Decimal = Decimal("0.1"),
                 asset_price_delegate: AssetPriceDelegate = None,
                 hb_app_notification: bool = False,
                 use_messari_api: bool = False,
                 messari_api_rate: int = 60,
                 order_override: Dict[str, List[str]] = {}):

        """
        :param market_infos: list of market trading pairs
        :param order_type: type of order to place
        :param floor_price: price to place the order at
        :param cancel_order_wait_time: how long to wait before cancelling an order
        :param is_buy: if the order is to buy
        :param time_delay: how long to wait between placing trades
        :param num_individual_orders: how many individual orders to split the order into
        :param total_order_amount: qty of the order to place
        :param total_order_per_session: qty limit to place for the trading session
        :param logging_options: select the types of logs to output
        :param status_report_interval: how often to report network connection related warnings, if any
        """

        if len(market_infos) < 1:
            raise ValueError(f"market_infos must not be empty.")

        super().__init__()
        self._market_infos = {
            (market_info.market, market_info.trading_pair): market_info
            for market_info in market_infos
        }
        self._market_info = market_infos[0]
        self._all_markets_ready = False
        self._place_orders = True
        self._logging_options = logging_options
        self._status_report_interval = status_report_interval
        self._time_delay = time_delay
        self._num_individual_orders = num_individual_orders
        self._quantity_remaining = total_order_amount
        self._time_to_cancel = {}
        self._order_type = order_type
        self._is_buy = is_buy
        self._total_order_amount = total_order_amount
        # number of sessiosn for trading
        self._num_trading_sessions = num_trading_sessions  # sessions left -> round(total_order_amount / total_order_per_session)
        # number of tokens to sell per session
        self._total_order_per_session = total_order_per_session
        self._session_tracking = {"count": num_trading_sessions, "total_order_per_session": total_order_per_session, "total_order_amount": total_order_amount,
                                  "session_duration": None, "last_hour_trading_volume": None, "buzzer_price_reached": None}
        self._first_order = True
        self._is_vwap = is_vwap
        self._percent_slippage = percent_slippage
        self._order_percent_of_volume = order_percent_of_volume
        self._has_outstanding_order = False

        self._trading_time_duration_secs = trading_time_duration * 3600
        self._bid_spread = bid_spread
        self._ask_spread = ask_spread
        self._order_levels = order_levels
        self._buy_levels = order_levels
        self._sell_levels = order_levels
        self._order_level_spread = order_level_spread
        self._order_level_amount = order_level_amount
        self._order_refresh_time = order_refresh_time
        self._order_refresh_tolerance_pct = order_refresh_tolerance_pct
        self._filled_order_delay = filled_order_delay
        self._inventory_skew_enabled = inventory_skew_enabled
        self._inventory_target_base_pct = inventory_target_base_pct
        self._inventory_range_multiplier = inventory_range_multiplier
        self._hanging_orders_enabled = hanging_orders_enabled
        self._hanging_orders_cancel_pct = hanging_orders_cancel_pct
        self._asset_price_delegate = asset_price_delegate
        self._order_override = order_override
        self._hb_app_notification = hb_app_notification

        self._buzzer_price = buzzer_price
        self._buzzer_percent = buzzer_percent
        self._use_messari_api = use_messari_api
        self._messari_api_rate = messari_api_rate

        if floor_price is not None:
            self._floor_price = floor_price
        if cancel_order_wait_time is not None:
            self._cancel_order_wait_time = cancel_order_wait_time

        if self._use_messari_api:
            trading_pair = str(self._market_info.trading_pair)
            exchange_name = self._market_info.market.name
            self.logger().info(f"Getting metrics for exchange: {exchange_name}")
            self._ms_obj = TokenMetrics(trading_pair.split("-")[0], exchange=exchange_name, verbose=True)
            self._session_tracking["last_hour_trading_volume"] = self._ms_obj.get_1hr_trading_volume_on_exchange()

        cdef:
            set all_markets = set([market_info.market for market_info in market_infos])

        self.c_add_markets(list(all_markets))

# begin - properties for script

    def all_markets_ready(self):
        return all([market.ready for market in self._sb_markets])

    @property
    def market_info(self) -> MarketTradingPairTuple:
        return self._market_info

    @property
    def trading_pair(self):
        return self._market_info.trading_pair

    @property
    def order_override(self):
        return self._order_override

    @order_override.setter
    def order_override(self, value: Dict[str, List[str]]):
        self._order_override = value

    @property
    def should_stop_trading(self):
        return self._should_stop_trading

    @should_stop_trading.setter
    def should_stop_trading(self, value: bool):
        self._should_stop_trading = value

    @property
    def order_refresh_tolerance_pct(self) -> Decimal:
        return self._order_refresh_tolerance_pct

    @order_refresh_tolerance_pct.setter
    def order_refresh_tolerance_pct(self, value: Decimal):
        self._order_refresh_tolerance_pct = value

    @property
    def order_amount(self) -> Decimal:
        return self._total_order_amount

    @order_amount.setter
    def order_amount(self, value: Decimal):
        self._total_order_amount = value

    @property
    def order_levels(self) -> int:
        return self._order_levels

    @order_levels.setter
    def order_levels(self, value: int):
        self._order_levels = value
        self._buy_levels = value
        self._sell_levels = value

    @property
    def buy_levels(self) -> int:
        return self._buy_levels

    @buy_levels.setter
    def buy_levels(self, value: int):
        self._buy_levels = value

    @property
    def sell_levels(self) -> int:
        return self._sell_levels

    @sell_levels.setter
    def sell_levels(self, value: int):
        self._sell_levels = value

    @property
    def order_level_amount(self) -> Decimal:
        return self._order_level_amount

    @order_level_amount.setter
    def order_level_amount(self, value: Decimal):
        self._order_level_amount = value

    @property
    def order_level_spread(self) -> Decimal:
        return self._order_level_spread

    @order_level_spread.setter
    def order_level_spread(self, value: Decimal):
        self._order_level_spread = value

    @property
    def inventory_skew_enabled(self) -> bool:
        return self._inventory_skew_enabled

    @inventory_skew_enabled.setter
    def inventory_skew_enabled(self, value: bool):
        self._inventory_skew_enabled = value

    @property
    def inventory_target_base_pct(self) -> Decimal:
        return self._inventory_target_base_pct

    @inventory_target_base_pct.setter
    def inventory_target_base_pct(self, value: Decimal):
        self._inventory_target_base_pct = value

    @property
    def inventory_range_multiplier(self) -> Decimal:
        return self._inventory_range_multiplier

    @inventory_range_multiplier.setter
    def inventory_range_multiplier(self, value: Decimal):
        self._inventory_range_multiplier = value

    @property
    def hanging_orders_enabled(self) -> bool:
        return self._hanging_orders_enabled

    @hanging_orders_enabled.setter
    def hanging_orders_enabled(self, value: bool):
        self._hanging_orders_enabled = value

    @property
    def hanging_orders_cancel_pct(self) -> Decimal:
        return self._hanging_orders_cancel_pct

    @hanging_orders_cancel_pct.setter
    def hanging_orders_cancel_pct(self, value: Decimal):
        self._hanging_orders_cancel_pct = value

    @property
    def bid_spread(self) -> Decimal:
        return self._bid_spread

    @bid_spread.setter
    def bid_spread(self, value: Decimal):
        self._bid_spread = value

    @property
    def ask_spread(self) -> Decimal:
        return self._ask_spread

    @ask_spread.setter
    def ask_spread(self, value: Decimal):
        self._ask_spread = value

    @property
    def order_optimization_enabled(self) -> bool:
        return self._order_optimization_enabled

    @order_optimization_enabled.setter
    def order_optimization_enabled(self, value: bool):
        self._order_optimization_enabled = value

    @property
    def order_refresh_time(self) -> float:
        return self._order_refresh_time

    @order_refresh_time.setter
    def order_refresh_time(self, value: float):
        self._order_refresh_time = value

    @property
    def filled_order_delay(self) -> float:
        return self._filled_order_delay

    @filled_order_delay.setter
    def filled_order_delay(self, value: float):
        self._filled_order_delay = value

    @property
    def filled_order_delay(self) -> float:
        return self._filled_order_delay

    @filled_order_delay.setter
    def filled_order_delay(self, value: float):
        self._filled_order_delay = value

    def get_mid_price(self) -> float:
        return self.c_get_mid_price()

    cdef object c_get_mid_price(self):
        cdef:
            AssetPriceDelegate delegate = self._asset_price_delegate
            object mid_price
        if self._asset_price_delegate is not None:
            mid_price = delegate.c_get_mid_price()
        else:
            mid_price = self._market_info.get_mid_price()
        return mid_price

    # "total_order_per_session", "is_vwap", "percent_slippage", "order_percent_of_volume", "messari_api_rate",
    # "time_delay", "floor_price", "cancel_order_wait_time", "buzzer_price", "buzzer_percent", "trading_time_duration"

    @property
    def total_order_per_session(self) -> Decimal:
        return self._session_tracking["total_order_per_session"]

    @total_order_per_session.setter
    def total_order_per_session(self, value: Decimal):
        # only set it the updated value is less than the total order amount and quantity remaining
        if value <= self._total_order_amount and value <= self._quantity_remaining:
            self._session_tracking["total_order_per_session"] = value

    @property
    def is_vwap(self) -> bool:
        return self._is_vwap

    @is_vwap.setter
    def is_vwap(self, value: bool):
        self._is_vwap = value

    @property
    def buzzer_price(self) -> float:
        return self._buzzer_price

    @buzzer_price.setter
    def buzzer_price(self, value: float):
        self._buzzer_price = value

    @property
    def buzzer_percent(self) -> float:
        return self._buzzer_percent

    @buzzer_percent.setter
    def buzzer_percent(self, value: float):
        self._buzzer_percent = value

    @property
    def trading_time_duration(self) -> float:
        return self._trading_time_duration_secs

    @trading_time_duration.setter
    def trading_time_duration(self, value: float):
        self._trading_time_duration_secs = value * 3600

    @property
    def percent_slippage(self) -> float:
        return self._percent_slippage

    @percent_slippage.setter
    def percent_slippage(self, value: float):
        self._percent_slippage = value

    @property
    def messari_api_rate(self) -> int:
        return self._messari_api_rate

    @messari_api_rate.setter
    def messari_api_rate(self, value: int):
        self._messari_api_rate = value

    @property
    def floor_price(self) -> float:
        return self._floor_price

    @floor_price.setter
    def floor_price(self, value: float):
        self._floor_price = value

    @property
    def time_delay(self) -> float:
        return self._time_delay

    @time_delay.setter
    def time_delay(self, value: float):
        self._time_delay = value

    @property
    def cancel_order_wait_time(self) -> float:
        return self._cancel_order_wait_time

    @cancel_order_wait_time.setter
    def cancel_order_wait_time(self, value: float):
        self._cancel_order_wait_time = value

# end - properties for script

    @property
    def active_bids(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_bids

    @property
    def active_asks(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_asks

    @property
    def active_limit_orders(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_limit_orders

    @property
    def in_flight_cancels(self) -> Dict[str, float]:
        return self._sb_order_tracker.in_flight_cancels

    @property
    def market_info_to_active_orders(self) -> Dict[MarketTradingPairTuple, List[LimitOrder]]:
        return self._sb_order_tracker.market_pair_to_active_orders

    @property
    def logging_options(self) -> int:
        return self._logging_options

    @logging_options.setter
    def logging_options(self, int64_t logging_options):
        self._logging_options = logging_options

    @property
    def place_orders(self):
        return self._place_orders

    def format_status(self) -> str:
        cdef:
            ExchangeBase maker_market
            OrderBook maker_order_book
            str maker_symbol
            str maker_base
            str maker_quote
            double maker_base_balance
            double maker_quote_balance
            list lines = []
            list warning_lines = []
            dict market_info_to_active_orders = self.market_info_to_active_orders
            list active_orders = []

        for market_info in self._market_infos.values():
            active_orders = self.market_info_to_active_orders.get(market_info, [])

            warning_lines.extend(self.network_warning([market_info]))

            markets_df = self.market_status_data_frame([market_info])
            lines.extend(["", "  Markets:"] + ["    " + line for line in str(markets_df).split("\n")])

            assets_df = self.wallet_balance_data_frame([market_info])
            lines.extend(["", "  Assets:"] + ["    " + line for line in str(assets_df).split("\n")])

            # See if there're any open orders.
            if len(active_orders) > 0:
                df = LimitOrder.to_pandas(active_orders)
                df_lines = str(df).split("\n")
                lines.extend(["", "  Active orders:"] +
                             ["    " + line for line in df_lines])
            else:
                lines.extend(["", "  No active maker orders."])

            warning_lines.extend(self.balance_warning([market_info]))

        if len(warning_lines) > 0:
            lines.extend(["", "*** WARNINGS ***"] + warning_lines)

        return "\n".join(lines)

    def stop_hb_app(self):
        if self._hb_app_notification:
            from hummingbot.client.hummingbot_application import HummingbotApplication
            HummingbotApplication.main_application()._handle_command("stop")

    cdef c_did_fill_order(self, object order_filled_event):
        """
        Output log for filled order.

        :param order_filled_event: Order filled event
        """
        cdef:
            str order_id = order_filled_event.order_id
            object market_info = self._sb_order_tracker.c_get_shadow_market_pair_from_order_id(order_id)
            tuple order_fill_record

        if market_info is not None:
            limit_order_record = self._sb_order_tracker.c_get_shadow_limit_order(order_id)
            order_fill_record = (limit_order_record, order_filled_event)

            if order_filled_event.trade_type is TradeType.BUY:
                if self._logging_options & self.OPTION_LOG_MAKER_ORDER_FILLED:
                    self.log_with_clock(
                        logging.INFO,
                        f"({market_info.trading_pair}) Limit buy order of "
                        f"{order_filled_event.amount} {market_info.base_asset} filled."
                    )
            else:
                if self._logging_options & self.OPTION_LOG_MAKER_ORDER_FILLED:
                    self.log_with_clock(
                        logging.INFO,
                        f"({market_info.trading_pair}) Limit sell order of "
                        f"{order_filled_event.amount} {market_info.base_asset} filled."
                    )

    cdef c_did_complete_buy_order(self, object order_completed_event):
        """
        Output log for completed buy order.

        :param order_completed_event: Order completed event
        """
        cdef:
            str order_id = order_completed_event.order_id
            object market_info = self._sb_order_tracker.c_get_market_pair_from_order_id(order_id)
            LimitOrder limit_order_record

        if market_info is not None:
            limit_order_record = self._sb_order_tracker.c_get_limit_order(market_info, order_id)
            # If its not market order
            if limit_order_record is not None:
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Limit buy order {order_id} "
                    f"({limit_order_record.quantity} {limit_order_record.base_currency} @ "
                    f"{limit_order_record.price} {limit_order_record.quote_currency}) has been filled."
                )
                self._session_tracking["total_order_per_session"] = Decimal(self._session_tracking["total_order_per_session"]) - Decimal(limit_order_record.quantity)
            else:
                market_order_record = self._sb_order_tracker.c_get_market_order(market_info, order_id)
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Market buy order {order_id} "
                    f"({market_order_record.amount} {market_order_record.base_asset}) has been filled."
                )
                self._session_tracking["total_order_per_session"] = Decimal(self._session_tracking["total_order_per_session"]) - Decimal(market_order_record.amount)
            self._has_outstanding_order = False

    cdef c_did_complete_sell_order(self, object order_completed_event):
        """
        Output log for completed sell order.

        :param order_completed_event: Order completed event
        """
        cdef:
            str order_id = order_completed_event.order_id
            object market_info = self._sb_order_tracker.c_get_market_pair_from_order_id(order_id)
            LimitOrder limit_order_record

        if market_info is not None:
            limit_order_record = self._sb_order_tracker.c_get_limit_order(market_info, order_id)
            # If its not market order
            if limit_order_record is not None:
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Limit sell order {order_id} "
                    f"({limit_order_record.quantity} {limit_order_record.base_currency} @ "
                    f"{limit_order_record.price} {limit_order_record.quote_currency}) has been filled."
                )
                self._session_tracking["total_order_per_session"] = Decimal(self._session_tracking["total_order_per_session"]) - Decimal(limit_order_record.quantity)
                self._session_tracking["total_order_amount"] = Decimal(self._session_tracking["total_order_amount"]) - Decimal(limit_order_record.quantity)
            else:
                market_order_record = self._sb_order_tracker.c_get_market_order(market_info, order_id)
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Market sell order {order_id} "
                    f"({market_order_record.amount} {market_order_record.base_asset}) has been filled."
                )
                self._session_tracking["total_order_per_session"] = Decimal(self._session_tracking["total_order_per_session"]) - Decimal(market_order_record.amount)
                self._session_tracking["total_order_amount"] = Decimal(self._session_tracking["total_order_amount"]) - Decimal(market_order_record.amount)
            self._has_outstanding_order = False

    cdef c_did_fail_order(self, object order_failed_event):
        if self._is_vwap:
            self.c_check_last_order(order_failed_event)

    cdef c_did_cancel_order(self, object cancelled_event):
        if self._is_vwap:
            self.c_check_last_order(cancelled_event)

    cdef c_did_expire_order(self, object expired_event):
        if self._is_vwap:
            self.c_check_last_order(expired_event)

    cdef c_start(self, Clock clock, double timestamp):
        self._trading_start_time = timestamp
        self._trading_volume_checkpoint_time = timestamp
        StrategyBase.c_start(self, clock, timestamp)
        self.logger().info(f"Waiting for {self._time_delay} to place orders")
        self._previous_timestamp = timestamp
        self._last_timestamp = timestamp
        self._session_tracking["session_duration"] = timestamp

    cdef c_tick(self, double timestamp):
        """
        Clock tick entry point.

        For this strategy, this function simply checks for the readiness and connection status of markets, and
        then delegates the processing of each market info to c_process_market().

        :param timestamp: current tick timestamp
        """
        StrategyBase.c_tick(self, timestamp)
        cdef:
            int64_t current_tick = <int64_t>(timestamp // self._status_report_interval)
            int64_t last_tick = <int64_t>(self._last_timestamp // self._status_report_interval)
            bint should_report_warnings = ((current_tick > last_tick) and
                                           (self._logging_options & self.OPTION_LOG_STATUS_REPORT))
            list active_maker_orders = self.active_limit_orders

        try:
            if not self._all_markets_ready:
                self._all_markets_ready = all([market.ready for market in self._sb_markets])
                if not self._all_markets_ready:
                    # Markets not ready yet. Don't do anything.
                    if should_report_warnings:
                        self.logger().warning(f"Markets are not ready. No market making trades are permitted.")
                    return

            if should_report_warnings:
                if not all([market.network_status is NetworkStatus.CONNECTED for market in self._sb_markets]):
                    self.logger().warning(f"WARNING: Some markets are not connected or are down at the moment. Market "
                                          f"making may be dangerous when markets or networks are unstable.")

            for market_info in self._market_infos.values():
                self.c_process_market(market_info)
        finally:
            self._last_timestamp = timestamp

    cdef c_check_last_order(self, object order_event):
        """
        Check to see if the event is called on an order made by this strategy. If it is made from this strategy,
        set self._has_outstanding_order to False to unblock further VWAP processes.
        """
        cdef:
            str order_id = order_event.order_id
            object market_info = self._sb_order_tracker.c_get_market_pair_from_order_id(order_id)
        if market_info is not None:
            self._has_outstanding_order = False

    cdef c_get_order_depth(self, num_entries):
        """
        Get the order book depth on the exchange.
        """
        cdef:
            OrderBook order_book = self.market_info.order_book
        orders = []
        count = 0
        if self._is_buy:  # buy
            for entry in order_book.bid_entries():
                orders.append(entry.amount); count += 1
                if count == num_entries:
                    break
        else:  # sell
            for entry in order_book.ask_entries():
                orders.append(entry.amount); count += 1
                if count == num_entries:
                    break
        orders = [order for order in orders if order <= self._total_order_per_session]
        # self.logger().info(f"Order sizes right now: {orders}")
        min_chunk = min(orders)
        max_chunk = max(orders)
        avg_chunk = round(sum(orders) / num_entries)
        self.logger().info(f"Order size range: {min_chunk},{max_chunk}. Avg = {avg_chunk}")
        return (min_chunk, max_chunk, avg_chunk)

    cdef c_place_orders(self, object market_info):
        """
        If TWAP, places an individual order specified by the user input if the user has enough balance and if the order quantity
        can be broken up to the number of desired orders

        Else, places an individual order capped at order_percent_of_volume * open order volume up to percent_slippage

        :param market_info: a market trading pair
        """
        cdef:
            ExchangeBase market = market_info.market
            object quantized_amount = Decimal(0)
            object quantized_price = market.c_quantize_order_price(market_info.trading_pair, Decimal(self._floor_price))
            OrderBook order_book = market_info.order_book

        if self._is_vwap:
            spot_price = order_book.c_get_price(self._is_buy)
            self.check_buzzer_price(spot_price)
            if self._session_tracking["buzzer_price_reached"] is True:
                fixed_rate = float(self._buzzer_percent / 100)
            else:
                fixed_rate = 0.01
            order_price = spot_price if self._order_type == "market" else max(self._floor_price, spot_price)
            slippage_amount = order_price * self._percent_slippage * 0.01
            if self._is_buy:
                slippage_price = order_price + slippage_amount
            else:
                slippage_price = order_price - slippage_amount

            if self._use_messari_api:
                # self.logger().info(f"Seconds since fetching trading volume: {self._current_timestamp - self._trading_volume_checkpoint_time}")
                if (self._current_timestamp - self._trading_volume_checkpoint_time) > self._messari_api_rate:
                    # self.logger().info("Fetching the latest trading volume info from Messari")
                    self._session_tracking["last_hour_trading_volume"] = self._ms_obj.get_1hr_trading_volume_on_exchange()
                    # checkpoint with the current timestamp
                    self._trading_volume_checkpoint_time = self._current_timestamp

                order_cap = self._order_percent_of_volume * self._session_tracking["last_hour_trading_volume"] * fixed_rate
                (_min, _max, _avg) = self.c_get_order_depth(10)
                if self._session_tracking["buzzer_price_reached"] is True:
                    if (order_cap + _avg) < _max:
                        order_cap += _avg
                else:
                    if order_cap < _avg:
                        order_cap = _avg  # use the avg if order_cap is below avg
                # _last_hour_trading_volume = self._session_tracking["last_hour_trading_volume"]
                # self.logger().info(f"Last hour of trading volume: {_last_hour_trading_volume}")
                quantized_amount = Decimal.from_float(order_cap)
                if quantized_amount > self._quantity_remaining:
                    quantized_amount = self._quantity_remaining
                quantized_price = Decimal.from_float(order_price)
            else:  # if not messari, then let's try the exchange
                total_order_volume = order_book.c_get_volume_for_price(self._is_buy, float(slippage_price))
                if total_order_volume.result_volume > 0:
                    # self.logger().info(f"Total order volume: {total_order_volume.result_volume}")
                    order_cap = self._order_percent_of_volume * total_order_volume.result_volume * 0.01
                    # self.logger().info(f"Order cap => {order_cap}")

                    quantized_amount = quantized_amount.min(Decimal.from_float(order_cap))
                    quantized_price = Decimal.from_float(order_price)
                else:
                    self.logger().info("No trading volume info available right now.")
                    self.stop_hb_app()
                    return

        self.logger().info(f"Placing order limit w/ amount => {round(quantized_amount, 6)}")

        self.logger().info(f"Checking to see if the user has enough balance to place orders")

        if quantized_amount != 0:
            if self.c_has_enough_balance(market_info):

                if self._order_type == "market":
                    if self._is_buy:
                        order_id = self.c_buy_with_specific_market(market_info,
                                                                   amount = quantized_amount)
                        self.logger().info("Market buy order has been executed")
                    else:
                        order_id = self.c_sell_with_specific_market(market_info,
                                                                    amount = quantized_amount)
                        self.logger().info("Market sell order has been executed")
                else:
                    if self._is_buy:
                        order_id = self.c_buy_with_specific_market(market_info,
                                                                   amount = quantized_amount,
                                                                   order_type = OrderType.LIMIT,
                                                                   price = quantized_price)
                        self.logger().info("Limit buy order has been placed")

                    else:
                        order_id = self.c_sell_with_specific_market(market_info,
                                                                    amount = quantized_amount,
                                                                    order_type = OrderType.LIMIT,
                                                                    price = quantized_price)
                        self.logger().info("Limit sell order has been placed")
                    self._time_to_cancel[order_id] = self._current_timestamp + self._cancel_order_wait_time

                self._quantity_remaining = Decimal(self._quantity_remaining) - quantized_amount
                self._has_outstanding_order = True

            else:
                self.logger().info(f"Not enough balance to run the strategy. Please check balances and try again.")
        else:
            self.logger().warning(f"Not possible to break the order into the desired number of segments.")

        # record session info
        self.record_session_info()
        # self.print_session_info()

    def record_session_info(self):
        if self._session_tracking["total_order_per_session"] <= 0:
            # reset the total for session
            self._session_tracking["total_order_per_session"] = self._total_order_per_session
            self._session_tracking["session_duration"] = self._current_timestamp - self._session_tracking["session_duration"]
            self._session_tracking["count"] -= 1

        return

    def print_session_info(self):
        self.logger().info(f"trading session info: {self._session_tracking}")
        return

    def check_buzzer_price(self, current_price):
        if current_price > self._buzzer_price:
            # accelrate order amounts by the specified percentage
            self._session_tracking["buzzer_price_reached"] = True
            return
        self._session_tracking["buzzer_price_reached"] = False

    cdef c_has_enough_balance(self, object market_info):
        """
        Checks to make sure the user has the sufficient balance in order to place the specified order

        :param market_info: a market trading pair
        :return: True if user has enough balance, False if not
        """
        cdef:
            ExchangeBase market = market_info.market
            double base_asset_balance = market.c_get_balance(market_info.base_asset)
            double quote_asset_balance = market.c_get_balance(market_info.quote_asset)
            OrderBook order_book = market_info.order_book
            double price = order_book.c_get_price_for_volume(True, float(self._quantity_remaining)).result_price

        return quote_asset_balance >= float(self._quantity_remaining) * price if self._is_buy else base_asset_balance >= float(self._quantity_remaining)

    cdef c_process_market(self, object market_info):
        """
        If the user selected TWAP, checks if enough time has elapsed from previous order to place order and if so, calls c_place_orders() and
        cancels orders if they are older than self._cancel_order_wait_time.

        Otherwise, if there is not an outstanding order, calls c_place_orders().

        :param market_info: a market trading pair
        """
        cdef:
            ExchangeBase maker_market = market_info.market
            set cancel_order_ids = set()

        # check if the current time is greater than trading time duration
        _trading_stop_time = self._current_timestamp - self._trading_start_time
        if (_trading_stop_time > self._trading_time_duration_secs) and not self._first_order:
            self.logger().info(f"Start time: "
                               f"{datetime.fromtimestamp(self._trading_start_time).strftime('%Y-%m-%d %H:%M:%S')} ")
            self.logger().info(f"Time to stop trading. Bot has been trading for over {self._trading_time_duration_secs / 3600} hours")
            # initiate stop command to hb
            self.stop_hb_app()
            return

        if not self._is_vwap:  # TWAP
            if self._quantity_remaining > 0:

                # If current timestamp is greater than the start timestamp and its the first order
                if self._current_timestamp > self._previous_timestamp and self._first_order:

                    self.logger().info(f"Trying to place orders now. ")
                    self._previous_timestamp = self._current_timestamp
                    self.c_place_orders(market_info)
                    self._first_order = False

                # If current timestamp is greater than the start timestamp + time delay place orders
                elif self._current_timestamp > self._previous_timestamp + self._time_delay and self._first_order is False:

                    self.logger().info(f"Current time: "
                                       f"{datetime.fromtimestamp(self._current_timestamp).strftime('%Y-%m-%d %H:%M:%S')} "
                                       f"is now greater than "
                                       f"Previous time: "
                                       f"{datetime.fromtimestamp(self._previous_timestamp).strftime('%Y-%m-%d %H:%M:%S')} "
                                       f" with time delay: {self._time_delay}. Trying to place orders now. ")
                    self._previous_timestamp = self._current_timestamp
                    self.c_place_orders(market_info)
        else:  # VWAP
            if not self._has_outstanding_order:
                self.c_place_orders(market_info)

        active_orders = self.market_info_to_active_orders.get(market_info, [])

        if len(active_orders) > 0:
            for active_order in active_orders:
                if self._current_timestamp >= self._time_to_cancel[active_order.client_order_id]:
                    cancel_order_ids.add(active_order.client_order_id)

        if len(cancel_order_ids) > 0:
            for order in cancel_order_ids:
                self.c_cancel_order(market_info, order)

        if self._quantity_remaining == 0:
            if not self._has_outstanding_order:
                if self._is_buy:
                    self.logger().info(f"Bought: {self._total_order_amount}")
                else:
                    self.logger().info(f"Sold: {self._total_order_amount}")
                self.print_session_info()
                self.stop_hb_app()
                return
