import sys
# 本体に、部品の preload と、部品を作る行を足す。使い方: wire.py 部品のクラス名 ファイル名 変数名 "説明"
cls, fname, var, desc = sys.argv[1:5]
p='scripts/prototype/stick_prototype.gd'; s=open(p).read()
a='const DamageNumbers := preload("res://scripts/ui/damage_numbers.gd")\n'
assert a in s
s=s.replace(a,a+'const %s := preload("res://scripts/prototype/%s")\n' % (cls,fname),1)
a='var rage := BossRage.new()'
i=s.index(a); j=s.index('\n',i)
s=s[:j+1]+'var %s := %s.new(self)  ## %s（%s）\n' % (var,cls,desc,fname)+s[j+1:]
open(p,'w').write(s)
