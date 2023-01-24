/*
import { connect } from 'react-redux';
import LivecureDropdown from '../components/livecure_dropdown';
import { toggleLivecuresVisibility } from '../../../actions/compose';
import { openModal, closeModal } from '../../../actions/modal';
import { isUserTouching } from '../../../is_mobile';

const mapStateToProps = state => ({
  isModalOpen: state.get('modal').modalType === 'ACTIONS',
  value: '',
});

const mapDispatchToProps = dispatch => ({

  onChange (value) {
    dispatch(toggleLivecuresVisibility(value));
  },

  isUserTouching,
  onModalOpen: props => dispatch(openModal('ACTIONS', props)),
  onModalClose: () => dispatch(closeModal()),

});

export default connect(mapStateToProps, mapDispatchToProps)(LivecureDropdown);
*/
