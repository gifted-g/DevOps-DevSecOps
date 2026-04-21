import sys

lines = open("/tmp/resource_samples.txt").readlines()
o2_cpu, o2_mem, os_cpu, os_mem = [], [], [], []
for line in lines:
    parts = line.split()
    if len(parts) >= 3:
        cpu = int(parts[1].replace('m',''))
        mem = int(parts[2].replace('Mi',''))
        if 'openobserve' in parts[0]:
            o2_cpu.append(cpu)
            o2_mem.append(mem)
        elif 'opensearch' in parts[0]:
            os_cpu.append(cpu)
            os_mem.append(mem)

if o2_cpu:
    print(f"O2_AVG_CPU={round(sum(o2_cpu)/len(o2_cpu))}m")
    print(f"O2_PEAK_CPU={max(o2_cpu)}m")
    print(f"O2_AVG_MEM={round(sum(o2_mem)/len(o2_mem))}Mi")
    print(f"O2_PEAK_MEM={max(o2_mem)}Mi")
else:
    print("O2_AVG_CPU=N/A")
    print("O2_PEAK_CPU=N/A")
    print("O2_AVG_MEM=N/A")
    print("O2_PEAK_MEM=N/A")

if os_cpu:
    print(f"OS_AVG_CPU={round(sum(os_cpu)/len(os_cpu))}m")
    print(f"OS_PEAK_CPU={max(os_cpu)}m")
    print(f"OS_AVG_MEM={round(sum(os_mem)/len(os_mem))}Mi")
    print(f"OS_PEAK_MEM={max(os_mem)}Mi")
else:
    print("OS_AVG_CPU=N/A")
    print("OS_PEAK_CPU=N/A")
    print("OS_AVG_MEM=N/A")
    print("OS_PEAK_MEM=N/A")
