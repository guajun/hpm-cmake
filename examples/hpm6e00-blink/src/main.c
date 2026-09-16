#include "board.h"

#define BLINK_HALF_PERIOD_MS (250U)

int main(void)
{
    board_init();
    board_init_led_pins();
    while (1) {
        board_led_write(BOARD_LED_ON_LEVEL);
        board_delay_ms(BLINK_HALF_PERIOD_MS);
        board_led_write(BOARD_LED_OFF_LEVEL);
        board_delay_ms(BLINK_HALF_PERIOD_MS);
    }
}
