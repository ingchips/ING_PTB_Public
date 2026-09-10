# 概述
该脚本用于生成 PTB 的配置文件，目前的配置结构体为：
```c
/*  high speed SPI0 clk config
    use "spi interface clock / (2 * (eSclkDiv + 1))" for calculation

    代码里面的 SPI0 的 spi interface clock 为 24M，eSclkDiv 对应的通信频率如下：
    SPI_24M = 0xFF,
    SPI_12M = 0x00,
    SPI_6M  = 0x01,
    SPI_4M  = 0x02,
    SPI_3M  = 0x03,
    SPI_2M4 = 0x04,
    SPI_2M  = 0x05,
*/
typedef struct{
	uint8_t tune；              // 为 PTB 自身的频偏校准值，范围0x00 - 0x3F，大于 0x3F 的值无效
	uint8_t swd_spi_sclkdiv;    // spi 的分频系数，对应的通信频率见上面注释
	uint16_t crc;
} ptb_config_t;
```
# 使用方法

`PTB_config.txt` 文件里面简写了配置项，可以通过文本来修改这些值
```
"tune":0xff
"swd_spi_sclkdiv":0xff
```

然后通过脚本生成 bin 文件，bin 文件烧录到 0x207F000 的位置，PTB 的代码上电会读取这个地址的配置，然后根据配置进行初始化。如果没有配置文件，使用默认配置。

## powershell 使用方式：
默认执行：
```
powershell -ExecutionPolicy Bypass -File .\generate_ptb_config.ps1
```

也可以指定输入和输出文件：
```
powershell -ExecutionPolicy Bypass -File .\generate_ptb_config.ps1 `
      .\PTB_config.txt `
      .\PTB_config.bin
```

## python 使用方式：
默认执行：
```
python .\generate_ptb_config.py
```

也支持指定输入输出文件：
```
python .\generate_ptb_config.py input.txt output.bin
```
