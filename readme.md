
# 通感算智一体化多机器人协同感知与决策系统

张同光1,2, 王欣溢1, 王方卓1, 凌陈昊3, 陶飞扬1, 贾鹏飛1

1. 新乡学院 3D打印学院，新乡 453003;
2. 北京邮电大学 网络与交换技术全国重点实验室, 北京 100876;
3. 河南师范大学 计算机与信息工程学院，新乡 453007

---

# 该仓库提供了整套项目源代码和实验视频

---

# 项目简介

为解决复杂动态环境下多机器人协同作业中跨机感知鲁棒性不足与队级决策实时性受限的问题，对通感算智一体化跨层闭环协同方法进行了研究，提出了一种多机器人协同感知与决策系统。该系统分层构建通信、多模态融合、边缘计算与多机协同决策，并以“感知融合→智能计算→协同决策→执行反馈→在线校准”形成闭环。感知侧设计置信度-距离-时效性动态加权融合及邻机共享目标融合算法，实现机载视觉检测、姿态信息与共享态势的自适应融合；决策侧融合优先级焦点、编队和受击救援机制；计算侧建立负载-时延感知的队列调度模型。仿真结果表明，非对称条件下有协同方胜率显著高于无协同方，双方有协同时对局时长明显缩短。

基于Godot 4.7物理引擎与GDExtension智能扩展构建验证平台。其中，Godot负责运动学仿真、传感器渲染与执行机构控制；设计的GDExtension共享库则对应边缘侧目标检测、视觉处理（相机分辨率设置为320×240、480×640）、融合与规划等核心功能。进程内模块间的目标信息共享机制在功能上映射为车际通信共享通道。平台将六台机器人置于约对抗场地，红蓝双方各3车、全自动控制。HP（Hit Points）为每台机器人装甲可承受的有效命中次数，取HP=5。每机4面装甲，累计有效命中达到5次即判定击毁（出局），击毁后残骸仍占据空间形成障碍，但不再计入命中与胜负统计。弹速约10 m/s。每局时限120 s。

评价指标：胜率、时长、定位误差、瞄准误差，以及协助次数、集火开火次数、救援事件、处理时间、队列和丢帧。协助表示跨机融合对本地瞄准/控制产生有效贡献的次数统计，用于衡量融合机制是否被激活。救援事件是有协同队伍中成员受击后触发“一方有难、八方支援”焦点切换的次数。集火开火是有协同条件下按队级优先级焦点实施射击的次数，用于刻画组织化火力而非随机射击。


# 测试命令 /root/lunwen/sim/run_paper_match.sh <编号> <局序号>。同一时间只开一局。

## 只开红方，20 局：

/root/lunwen/sim/run_paper_match.sh W_redfull 2

## 只开蓝方，20 局：

/root/lunwen/sim/run_paper_match.sh W_bluefull 1

## 双方都开、双方都关，各 20 局：

/root/lunwen/sim/run_paper_match.sh S_bothon 1

/root/lunwen/sim/run_paper_match.sh S_bothoff 1

## 每次只关一个模块，各 10 局。奇数局红方全开，偶数局蓝方全开：

/root/lunwen/sim/run_paper_match.sh L_fusion 1

/root/lunwen/sim/run_paper_match.sh L_focus 1

/root/lunwen/sim/run_paper_match.sh L_formation 1

/root/lunwen/sim/run_paper_match.sh L_rescue 1

## 双方都开的信道、分辨率和距离检查，各 10 局：

/root/lunwen/sim/run_paper_match.sh C_d100 1

/root/lunwen/sim/run_paper_match.sh C_d400 1

/root/lunwen/sim/run_paper_match.sh C_d100_loss 1

/root/lunwen/sim/run_paper_match.sh P_640 1

/root/lunwen/sim/run_paper_match.sh G_gateoff 1

## 双方四个开关都打开，各 10 局：

/root/lunwen/sim/run_paper_match.sh B_proposed 1

/root/lunwen/sim/run_paper_match.sh B_uniform 1

/root/lunwen/sim/run_paper_match.sh B_nearest 1

/root/lunwen/sim/run_paper_match.sh B_eq 1

/root/lunwen/sim/run_paper_match.sh B_lam05 1

/root/lunwen/sim/run_paper_match.sh B_lam20 1

/root/lunwen/sim/run_paper_match.sh B_d400 1

/root/lunwen/sim/run_paper_match.sh B_calib0 1

/root/lunwen/sim/run_paper_match.sh B_calib400 1
