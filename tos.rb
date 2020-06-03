#coding: utf-8
require 'gosu'
require 'aasm'
require_relative 'stone'
require_relative 'board'
require_relative 'timebar'
require_relative 'team'
require_relative 'floor'

class BATTLE_STATE
  include AASM
  aasm do
    state :normal, initial: true
    state :moveing,:deleting,:dropping,:checking,:attacking,:first_checking
		state :first_deleting, :first_dropping
		state :enemy_attacking
		
		event :first_delete do; transitions from: :moveing, to: :first_deleting; end
		event :first_drop do; transitions from: :first_deleting, to: :first_dropping; end
		event :enemy_attack do; transitions from: :attacking, to: :enemy_attacking; end
		
		event :move do
			transitions from: :normal, to: :moveing
		end
		event :active do
			transitions from: :normal, to: :first_checking
		end
		
		event :delete do
			transitions from: :moveing, to: :deleting
		end		
		event :drop do
			transitions from: [:deleting,:checking], to: :dropping
		end
		event :again do
			transitions from: :dropping, to: :deleting
		end
		event :check do
			transitions  from: :dropping, to: :checking
		end
		event :attack do
			transitions from: :checking, to: :attacking
		end
		
		# test
		event :back do
			transitions from: [:enemy_attacking,:first_checking,:moveing,:deleting,:dropping,:attacking], to: :normal
		end
		
	end
end

class Game < Gosu::Window
	
	def initialize
		super 480,720
		#super 1200,720
		self.caption = "ToS"
		@board = Board.new
		@team = Team.new([1239,1224,1239,1239,1239,1239])
		@timebar = Timebar.new(@team.maxLife)
		@state = BATTLE_STATE.new
		@floor = Floor.new(2)
		
		@debug = Gosu::Font.new(25)
		
	end
	def needs_cursor?; true; end

	def update
		mx,my = mouse_x,mouse_y
		sx,sy = width,height
		currtime = Gosu.milliseconds
		
		button_down?(Gosu::KB_ESCAPE) and exit
		
		# 轉珠前
		if button_down?(Gosu::MS_LEFT) and @state.may_move?
			if @board.stone?(mx,my)
				@board.reset_combo_counter
				@board.drag(mx,my)
				@board.swap(mx,my) and @state.move
			end
			if @team.monster?(mx,my)
				i = @team.index(mx,my)
				@team.can_active?(i) and active_monster_skill(i) & @team.active(i)
			end
		end
		# 轉珠中
		if button_down?(Gosu::MS_LEFT) and @state.moveing?
			# 時間結束計算combo		
			@timebar.countdown(currtime) and @state.delete and @board.check_combos
		end
		if button_down?(Gosu::MS_LEFT) and @state.moveing? and @board.stone?(mx,my)
			@board.drag(mx,my)
			@board.swap(mx,my)
		elsif !button_down?(Gosu::MS_LEFT) and @state.moveing?
			@timebar.reset_timebar
			# 放開後珠子計算combo
			@board.check_combos
			@state.delete
		end
		# 刪除動畫
		if @state.deleting?
			@board.all_delete? and @state.drop and @board.search_dropping
			@board.delete_combos(currtime)
		end
		
		if @state.dropping?
			if @board.dropping
				@board.check_combos
				
				if @board.all_delete?
					@state.check
				else
					@state.again
				end
			end
		end
		if @state.checking?
			#if @board.explode_h
			#	@state.drop and @board.search_dropping
			#else
				@state.attack
			#end
		end
		
		# 計算傷害
		if @state.attacking?
			@team.charge
			@team.recovery
			@state.enemy_attack
		end
		
		if @state.first_checking?
			@state.back
		end
		
		if @state.enemy_attacking?
			@floor.cd_countdown
			@team.take_damage(@floor.damage)
			
			@state.back
		end
		
		!button_down?(Gosu::MS_LEFT) || @state.deleting? and @board.reset	
		
		!@state.moveing? and !@state.normal? and !@state.dropping? and calculate_atk & calculate_re
		@timebar.update_life(@team.currLife)
		@floor.update
		# test
		button_down?(Gosu::KB_Q) and @board.new
		button_down?(Gosu::KB_R) and @state.back
		
	end
	
	def draw
		mx,my = mouse_x,mouse_y
		sx,sy = width,height
		@board.draw
		
		@floor.draw_enemys
		
		@team.draw_icon
		@state.normal? and @team.monster?(mx,my) and @team.draw_skill(@team.index(mx,my))
		!@state.normal? and !@state.moveing? and @team.draw_atk
		!@state.normal? and !@state.moveing? and @timebar.draw_re(@team.total_re)
		
		!@state.normal? and !@state.moveing? and @board.draw_combo
		!@state.moveing? and @timebar.draw_lifebar
		@state.moveing? and @timebar.draw_timebar
		
		
		#@debug.draw_text("#{mx} , #{my}", 0, 0, 2, 1.0, 1.0, Gosu::Color::WHITE)

		#@debug.draw_text("center", 200, 100, 2, 1.0, 1.0, Gosu::Color::WHITE)

	end
	
	private
	def active_monster_skill(monsterOrder)
		monsterId = @team.id(monsterOrder)
		case monsterId
			when 1224
			when 1239
				@board.all_transform
				@board.enchante("_f")
		end
		@state.active
	end
	def map_leader_skill(leader,target)
		magn = 1.0
		case leader.id
			when 1239
				if target.attr == "_f"
					magn = 3.2
					if @board.dissolving_types >= 4
						magn *= 1.8
					elsif @board.dissolving_3_types?
						magn *= 1.5
					end
				end
		end
		return magn
	end
	def calculate_atk
		leader1 = @team.first_leader
		leader2 = @team.second_leader
		@team.monsters.each do |m|
			atk = m.atk
			atk *= map_leader_skill(leader1, m)
			atk *= map_leader_skill(leader2, m)
			atk *= @board.calculate_atk(m.attr)
			m.update_atk(atk.floor)
		end
	end
	def calculate_re
		leader1 = @team.first_leader
		leader2 = @team.second_leader
		@team.monsters.each do |m|
			re = m.re
			re *= @board.calculate_re
			m.update_re(re.floor)
		end
	end
end

Game.new.show
