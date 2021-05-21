# distutils: language=c++

from hummingbot.strategy.strategy_base cimport StrategyBase
from libc.stdint cimport int64_t

cdef class VwapTradeStrategy(StrategyBase):
    cdef:
        dict _market_infos
        object _market_info
        bint _all_markets_ready
        bint _place_orders
        bint _is_buy
        str _order_type
        bint _should_stop_trading

        # fields to support script capabilities
        object _bid_spread
        object _ask_spread
        object _minimum_spread
        int _order_levels
        int _buy_levels
        int _sell_levels
        object _order_level_spread
        object _order_level_amount
        double _order_refresh_time
        object _order_refresh_tolerance_pct
        double _filled_order_delay
        bint _hanging_orders_enabled
        object _hanging_orders_cancel_pct
        bint _inventory_skew_enabled
        object _inventory_target_base_pct
        object _inventory_range_multiplier
        object _order_override
        object _asset_price_delegate

        double _cancel_order_wait_time
        double _status_report_interval
        double _last_timestamp
        double _previous_timestamp
        double _time_delay
        int _num_individual_orders
        int _num_trading_sessions
        double _floor_price
        double _buzzer_price
        double _buzzer_percent
        object _total_order_amount
        object _total_order_per_session
        object _quantity_remaining
        bint _first_order
        double _trading_time_duration_secs
        double _trading_start_time
        double _trading_volume_checkpoint_time
        double _last_hour_trading_volume
        bint _is_vwap
        bint _use_messari_api
        object _ms_obj
        double _percent_slippage
        double _order_percent_of_volume
        bint _has_outstanding_order

        dict _tracked_orders
        dict _time_to_cancel
        dict _order_id_to_market_info
        dict _in_flight_cancels
        bint _hb_app_notification

        int64_t _logging_options

    cdef object c_get_mid_price(self)
    cdef c_check_last_order(self, object order_event)
    cdef c_process_market(self, object market_info)
    cdef c_place_orders(self, object market_info)
    cdef c_has_enough_balance(self, object market_info)
    cdef c_process_market(self, object market_info)
