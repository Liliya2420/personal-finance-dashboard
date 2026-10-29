*******************************************************************************
*  描述性统计表生成器  ——  兼容 Stata 12（不用装任何外部命令）
*
*  怎么用：
*    1. 打开 Stata 12
*    2. File -> Open，文件类型选 Do-files (*.do)，打开这个文件
*    3. 按 Ctrl + D 运行（或点工具栏上那个带箭头的 Do 按钮）
*    4. 会出来两样东西：
*         - 屏幕上直接显示的表格
*         - 一个 .csv 文件，Excel / WPS 双击就能打开，可以直接粘进 Word 当论文表格
*         - 外加一个 .log 文件，记录全部运行过程
*       文件位置 = Stata 当前工作目录，运行一开始屏幕上会告诉你
*
*  重要提醒：强烈建议把这个 .do 文件放在纯英文路径下，
*          例如 E:\stata_work\ ；放在中文路径里 Stata 12 有时会读不出来
*******************************************************************************

clear all
set more off
capture log close

* 想把文件生成到别处，把下面这行的 * 去掉并改成你的路径（用英文）
* cd "E:\stata_work"

display _n "工作目录（生成的文件都在这里找）： `c(pwd)'"
log using "descriptive_stats.log", replace text


*******************************************************************************
*  只要改下面这一段，其它地方都不用动
*******************************************************************************

* 1. 数据集名字
*    Stata 12 自带的数据集有这些：auto  nlsw88  census  lifeexp  citytemp
*                                sp500  educ99gdp  voter  pop2000  bplong
global mydata  "nlsw88"

* 2. 数据从哪来
*    sysuse = 用 Stata 自带的，不用联网（新手推荐这个）
*    webuse = 联网从官网下载（需要能连 github/stata 的网）
*    use    = 读你自己电脑上的文件，这时候要在第 3 行填完整路径
global howuse  "sysuse"

* 3. 只有上面选了 use 才需要填，路径里要写两个反斜杠
*    global mypath "E:\\stata_work\\mydata.dta"
global mypath  ""

* 4. 要分析的两个变量，空格隔开
*    想换成配套的另外两个，直接改这一行就行
global myvars  "wage hours"

* 5. 分组变量：留空 = 不做分组
*    填上一个分类变量（比如 union、collgrad、race），最后会多出一张分组对比表
global mygroup ""

* 6. 输出的 csv 文件名（建议英文）
global outname "descriptive_stats"

*******************************************************************************
*  下面是正式计算过程
*******************************************************************************

* ---------- 第 1 步：读入数据 ----------
local okuse = 0
foreach t in sysuse webuse use {
    if "$howuse" == "`t'" local okuse = 1
}
if `okuse' == 0 {
    display as error "howuse 这一行只能填 sysuse / webuse / use，你现在填的是：$howuse"
    exit 198
}

if "$howuse" == "sysuse" sysuse $mydata, clear
if "$howuse" == "webuse" webuse $mydata, clear
if "$howuse" == "use"    use `"$mypath"', clear

* ---------- 第 2 步：先检查你填的变量有没有问题 ----------
local nv : word count $myvars
if `nv' == 0 {
    display as error "myvars 是空的，请至少填一个变量名"
    exit 111
}

foreach v of global myvars {
    capture confirm variable `v'
    if _rc != 0 {
        display as error "变量 `v' 在这个数据集里不存在。"
        display as error "解决办法：在命令窗口敲 describe，看清楚变量名再改 myvars 那一行。"
        exit 111
    }
    capture confirm numeric variable `v'
    if _rc != 0 {
        display as error "变量 `v' 是文字型的，算不了均值和标准差，请换一个数值变量。"
        exit 111
    }
}

display _n "==================== 数据概况 ===================="
describe, short
display "样本行数：" _N

display _n "==================== 缺失值检查 ===================="
foreach v of global myvars {
    quietly count if missing(`v')
    display "变量 `v'   缺失个数 = " r(N)
}

* ---------- 第 3 步：算出 10 个统计量，存进矩阵 ----------
* 10 行 = 10 个统计量；`nv' 列 = 你填的每个变量
local slam "观测值 均值 标准差 最小值 25分位数 中位数 75分位数 最大值 偏度 峰度"
local nstat = 10

matrix dstats = J(`nstat', `nv', .)

local j = 1
foreach v of global myvars {
    quietly summarize `v', detail
    matrix dstats[1,  `j'] = r(N)
    matrix dstats[2,  `j'] = r(mean)
    matrix dstats[3,  `j'] = r(sd)
    matrix dstats[4,  `j'] = r(min)
    matrix dstats[5,  `j'] = r(p25)
    matrix dstats[6,  `j'] = r(p50)
    matrix dstats[7,  `j'] = r(p75)
    matrix dstats[8,  `j'] = r(max)
    matrix dstats[9,  `j'] = r(skewness)
    matrix dstats[10, `j'] = r(kurtosis)
    local j = `j' + 1
}

matrix rownames dstats = `slam'
matrix colnames dstats = $myvars

* ---------- 第 4 步：把表格打印到屏幕上 ----------
display _n "=========================================================="
display "                   表 1   描述性统计"
display "=========================================================="
matrix list dstats, noblank format(%10.3f)
display "----------------------------------------------------------"
display "数据来源：$mydata"
display "注：每个变量各自剔除缺失值后再计算，所以各列 N 可能不同。"
display "    偏度 0 = 左右对称；峰度 3 = 正态分布。"
display "=========================================================="

* ---------- 第 5 步：导出成 csv（Excel / WPS 可直接打开） ----------
* 如果同名 csv 正被 Excel 打开着，文件会被锁住写不进去。
* 下面这段会自动换个名字重试，并把换名字的事告诉你。
local opened = 0
foreach cand in "$outname" "${outname}_new" "${outname}_new2" {
    capture file open tbl using "`cand'.csv", write replace
    if _rc == 0 {
        local fname "`cand'"
        local opened = 1
        continue, break
    }
}

if `opened' == 1 {
    file write tbl "统计量"
    foreach v of global myvars {
        file write tbl ",`v'"
    }
    file write tbl _n

    file write tbl "变量含义"
    foreach v of global myvars {
        local thislab : variable label `v'
        file write tbl ",`thislab'"
    }
    file write tbl _n

    forvalues i = 1/`nstat' {
        local lab : word `i' of `slam'
        file write tbl "`lab'"
        forvalues j = 1/`nv' {
            local val = trim(string(dstats[`i',`j'], "%12.4f"))
            file write tbl ",`val'"
        }
        file write tbl _n
    }

    file write tbl _n
    file write tbl "数据来源,$mydata" _n
    file write tbl "注,各变量分别剔除缺失值；偏度 0 表示对称，峰度 3 表示正态分布" _n
    file close tbl

    display _n "已生成表格文件：`fname'.csv"
    if "`fname'" != "$outname" {
        display as text "注意：原来的 $outname.csv 正被 Excel / WPS 打开着，文件锁住了。"
        display as text "      所以这次换了个名字存。想覆盖原文件，先关掉 Excel 再运行。"
    }
}
else {
    display as error "csv 导出失败。请把 Excel / WPS 里打开的 csv 关掉，再运行一次。"
}

* ---------- 第 6 步（可选）：分组描述性统计 ----------
if "$mygroup" != "" {
    capture confirm variable $mygroup
    if _rc == 0 {
        display _n "=========================================================="
        display "          按 $mygroup 分组的描述性统计"
        display "=========================================================="
        tabstat $myvars, by($mygroup) stat(n mean sd min max)      ///
                col(stat) format(%9.3f) nototal
    }
    else {
        display as error "分组变量 $mygroup 不存在，分组表已跳过"
    }
}

* ---------- 想继续跑回归的话，把下面这行开头的 * 去掉 ----------
* regress wage hours

log close
display _n "全部完成。输出文件在：`c(pwd)'"
