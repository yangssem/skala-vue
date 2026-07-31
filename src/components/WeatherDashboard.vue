<script setup>
import { computed, ref } from 'vue'

// Backend에서 받았다고 가정하는 날씨 데이터
const weatherList = ref([
  { id: 'city_01', name: '서울', temp: 28, status: '맑음' },
  { id: 'city_02', name: '수원', temp: 24, status: '비' },
  { id: 'city_03', name: '부산', temp: 26, status: '구름' },
])

const searchKeyword = ref('서울')
const showHotOnly = ref(false)
const selectedCity = ref(weatherList.value[0])

// :value와 @input을 결합해 입력값을 즉시 동기화한다.
function updateSearchKeyword(event) {
  searchKeyword.value = event.target.value
}

// 검색어와 옵션이 바뀔 때마다 화면에 표시할 배열을 다시 계산한다.
const filteredWeatherList = computed(() => {
  const keyword = searchKeyword.value.trim()

  return weatherList.value.filter((weather) => {
    const matchesKeyword = weather.name.includes(keyword)
    const matchesTemperature = !showHotOnly.value || weather.temp >= 25

    return matchesKeyword && matchesTemperature
  })
})

function selectCity(weather) {
  selectedCity.value = weather
}

function showDetails(weather) {
  window.alert(
    `${weather.name} 날씨 안내\n현재 기온: ${weather.temp}℃\n날씨 상태: ${weather.status}`,
  )
}
</script>

<template>
  <section class="dashboard">
    <header class="dashboard__header">
      <p class="dashboard__eyebrow">VUE DIRECTIVE PRACTICE</p>
      <h1>🌤️ 날씨 대시보드</h1>
      <p>도시를 검색하고, 조건에 맞는 날씨 카드를 확인해 보세요.</p>
    </header>

    <section class="panel search-panel">
      <div class="section-title">
        <span class="section-title__icon">🔍</span>
        <div>
          <h2>도시 검색</h2>
          <p>한글 입력값이 목록에 즉시 반영됩니다.</p>
        </div>
      </div>

      <label class="search-label" for="city-search">도시 이름</label>
      <input
        id="city-search"
        class="search-input"
        type="search"
        placeholder="예: 서울"
        :value="searchKeyword"
        @input="updateSearchKeyword"
      />

      <div class="search-options">
        <p>
          검색 중인 도시:
          <strong>{{ searchKeyword || '전체' }}</strong>
        </p>

        <label class="checkbox-option">
          <input v-model="showHotOnly" type="checkbox" />
          25℃ 이상만 보기
        </label>
      </div>
    </section>

    <section class="panel weather-panel">
      <div class="section-title">
        <span class="section-title__icon">🏙️</span>
        <div>
          <h2>지역별 날씨 현황</h2>
          <p>{{ filteredWeatherList.length }}개의 도시가 검색되었습니다.</p>
        </div>
      </div>

      <div v-if="filteredWeatherList.length" class="weather-list">
        <article
          v-for="weather in filteredWeatherList"
          :key="weather.id"
          class="weather-card"
          :class="{ 'weather-card--selected': selectedCity?.id === weather.id }"
          tabindex="0"
          @click="selectCity(weather)"
          @keydown.enter="selectCity(weather)"
        >
          <div>
            <h3>{{ weather.name }} <span>({{ weather.status }})</span></h3>
            <p class="temperature">현재 기온: <strong>{{ weather.temp }}℃</strong></p>

            <span v-if="weather.temp >= 25" class="temperature-label temperature-label--hot">
              🔥 더움 (25도 이상)
            </span>
            <span v-else class="temperature-label temperature-label--cool">
              ❄️ 선선함 (25도 미만)
            </span>
          </div>

          <button class="detail-button" type="button" @click.stop="showDetails(weather)">
            상세보기
          </button>
        </article>
      </div>

      <div v-else class="empty-state">
        <span>🔎</span>
        <p>검색 조건에 맞는 도시가 없습니다.</p>
      </div>
    </section>

    <footer v-if="selectedCity" class="selection-result">
      <span>✓</span>
      <strong>{{ selectedCity.name }}</strong>이(가) 선택되었습니다.
    </footer>
  </section>
</template>
